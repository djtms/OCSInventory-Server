################################################################################
## OCSINVENTORY-NG 
## Copyleft Pascal DANEK 2008
## Web : http://www.ocsinventory-ng.org
##
## This code is open source and may be copied and modified as long as the source
## code is always made freely available.
## Please refer to the General Public Licence http://www.gnu.org/ or Licence.txt
################################################################################
package Apache::Ocsinventory::Server::Capacities::Notify;

use strict;

BEGIN{
  if($ENV{'OCS_MODPERL_VERSION'} == 1){
    require Apache::Ocsinventory::Server::Modperl1;
    Apache::Ocsinventory::Server::Modperl1->import();
  }elsif($ENV{'OCS_MODPERL_VERSION'} == 2){
    require Apache::Ocsinventory::Server::Modperl2;
    Apache::Ocsinventory::Server::Modperl2->import();
  }
}

use Apache::Ocsinventory::Map;
use Apache::Ocsinventory::Server::System;
use Apache::Ocsinventory::Server::Communication;
use Apache::Ocsinventory::Server::Constants;

# Initialize option
push @{$Apache::Ocsinventory::OPTIONS_STRUCTURE},{
  'NAME' => 'NOTIFY',
  'HANDLER_PROLOG_READ' => undef,
  'HANDLER_PROLOG_RESP' => undef,
  'HANDLER_PRE_INVENTORY' => undef,
  'HANDLER_POST_INVENTORY' => undef,
  'REQUEST_NAME' => 'NOTIFY',
  'HANDLER_REQUEST' => \&notify_handler,
  'HANDLER_DUPLICATE' => undef,
  'TYPE' => OPTION_TYPE_ASYNC,
  'XML_PARSER_OPT' => {
      'ForceArray' => ['IFACE']
  }
};
sub notify_handler{
  my $current_context = shift;
  
  if( !$current_context->{EXIST_FL} ){
    &_log(322, 'notify', 'no_device');
    return APACHE_OK;
  }
  
  &_log(322, 'notify', $current_context->{'XML_ENTRY'}->{TYPE});
  if( $current_context->{'XML_ENTRY'}->{TYPE} eq 'IP' ){
    &update_ip( $current_context );
  }
  else{
    &_log(529, 'notify', 'not_supported');
  }
  return APACHE_OK;
}

sub update_ip{
  # Initialize data
  my $current_context = shift;
  my $update_hardware;
  
  my $dbh    = $current_context->{'DBI_HANDLE'};
  my $result  = $current_context->{'XML_ENTRY'};
  my $hardwareId = $current_context->{'DATABASE_ID'};
  
  my $select_h_sql = 'SELECT IPADDR,MACADDR FROM hardware h,networks n WHERE IPADDR=IPADDRESS AND h.ID=?';
  my $updateMainIp_sql = 'UPDATE hardware SET IPADDR=? WHERE ID=?';

  
  # Get default IP
  my $sth = $dbh->prepare( $select_h_sql );
  $sth->execute( $hardwareId );
  my $row = $sth->fetchrow_hashref;
  my $defaultIface = $row->{MACADDR};
  my $defaultIp = $row->{IPADDR};
  $sth->finish;
    
  if( exists $result->{IFACE} ){
    for my $newIface ( @{$result->{IFACE}} ){
      next if !$newIface->{IP} or !$newIface->{MASK} or !$newIface->{MAC};

      my (@update_fields, @update_values);

      #We create update request using existing values only
      if ($newIface->{GW}) { push @update_fields,'IPGATEWAY=?'; push @update_values,$newIface->{GW}; }
      if ($newIface->{DHCP}) { push @update_fields,'IPDHCP=?'; push @update_values,$newIface->{DHCP}; }
      if ($newIface->{SUBNET}) { push @update_fields,'IPSUBNET=?'; push @update_values,$newIface->{SUBNET}; }
      if ($newIface->{IP}) { push @update_fields,'IPADDRESS=?'; push @update_values,$newIface->{IP}; }
      if ($newIface->{MASK}) { push @update_fields,'IPMASK=?'; push @update_values,$newIface->{MASK}; }
      push @update_values,$newIface->{MAC};
      push @update_values,$hardwareId;

      my $updateIp_sql= 'UPDATE networks SET '.(join ',', @update_fields).' WHERE MACADDR=? AND HARDWARE_ID=?';

      my $err = $dbh->do( $updateIp_sql, {}, @update_values );
      if( !$err ){
        &_log(530, 'notify', 'error');
      }
      elsif( $err==0E0 ){
        &_log(324, 'notify', $newIface->{MAC});     
      }
      else{
        &_log(323, 'notify', "$newIface->{MAC}<$newIface->{IP}>");

        if (exists $result->{HARDWARE}) {   #New behaviour with additional <HARDWARE> tag 
          $dbh->do( $updateMainIp_sql, {}, $result->{HARDWARE}->{IPADDR}, $hardwareId);
	  $update_hardware = 1;
        }

	#We update CHECKSUM value in hardware table
	my $mask = $DATA_MAP{networks}{mask};         
	$mask = $mask|1 if $update_hardware; 
	$dbh->do("UPDATE hardware SET CHECKSUM=($mask|CHECKSUM) WHERE ID=$hardwareId");
      }  
    }
  }
}
1;

