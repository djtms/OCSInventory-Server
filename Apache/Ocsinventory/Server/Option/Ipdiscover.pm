###############################################################################
## OCSINVENTORY-NG 
## Copyleft Pascal DANEK 2005
## Web : http://ocsinventory.sourceforge.net
##
## This code is open source and may be copied and modified as long as the source
## code is always made freely available.
## Please refer to the General Public Licence http://www.gnu.org/ or Licence.txt
################################################################################
package Apache::Ocsinventory;

use strict;

our %CURRENT_CONTEXT;

BEGIN{
	# Initialize option
	push @{$Apache::Ocsinventory::OPTIONS_STRUCTURE},{
		"HANDLER_PROLOG_READ" => undef,
		"HANDLER_PROLOG_RESP" => \&_ipdiscover_prolog_resp,
		"HANDLER_INVENTORY" => \&_ipdiscover_main,
		"REQUEST_NAME" => undef,
		"HANDLER_REQUEST" => undef,
		"HANDLER_DUPLICATE" => undef,
		"TYPE" => OPTION_TYPE_SYNC
	};
}

# Default
$Apache::Ocsinventory::OPTIONS{"OCS_OPT_IPDISCOVER"} = 1;
$Apache::Ocsinventory::OPTIONS{"OCS_OPT_IPDISCOVER_MAX_ALIVE"} = 14;

sub _ipdiscover_prolog_resp{

	return unless $ENV{'OCS_OPT_IPDISCOVER'};

	my $resp = shift;
	my $request;
	my $row;
	my $dbh = $CURRENT_CONTEXT{"DBI_HANDLE"};
	my $DeviceID = $CURRENT_CONTEXT{"DEVICEID"};

	################################
	#IPDISCOVER
	###########
	# What is the current state of this option ?

	#ipdiscover for this device ?
	$request=$dbh->prepare('SELECT TVALUE FROM devices WHERE DEVICEID='.$dbh->quote($DeviceID).' AND NAME="IPDISCOVER"');
	$request->execute();
	if($request->rows){
		$resp->{'RESPONSE'} = [ "SEND" ];
		$row = $request->fetchrow_hashref();
		push @{$$resp{'OPTION'}}, { 'NAME' => [ 'IPDISCOVER' ], 'PARAM' => [ $row->{'TVALUE'} ]};
		&_set_http_header('Connection', 'close');
		return(1);
	}else{
		return(0);
	}
}

sub _ipdiscover_main{

	my $request;
	my $row;
	my $subnet;
	my $remove;
	my $result;

	return unless $ENV{OCS_OPT_IPDISCOVER};
	
	my $DeviceID = $CURRENT_CONTEXT{"DEVICEID"};
	my $dbh = $CURRENT_CONTEXT{"DBI_HANDLE"};
	my $data = $CURRENT_CONTEXT{"DATA"};

	unless($result = XML::Simple::XMLin( $$data, SuppressEmpty => 1, ForceArray => ['H', 'NETWORKS'] )){
		return(1);
	}

	# Is the device already have the ipdiscover function ?
	$request=$dbh->prepare('SELECT TVALUE FROM devices WHERE DEVICEID='.$dbh->quote($DeviceID).' AND NAME="IPDISCOVER"');
	$request->execute();
	if($request->rows){
		$row = $request->fetchrow_hashref;
		# get 1 on removing and 0 if ok
		$remove = &_ipdiscover_read_result($result, $row->{'TVALUE'});
		$request->finish;
		if(!defined($remove)){
			return(1);
		}
	}else{
		if($result->{CONTENT}->{HARDWARE}->{OSNAME}!~/xp|2000|linux/i){
			return(0);
		}
		
		# Get quality and fidelity
		$request = $dbh->prepare('SELECT QUALITY,FIDELITY FROM hardware WHERE DEVICEID='.$dbh->quote($DeviceID));
		$request->execute();

		if($row = $request->fetchrow_hashref){
	  		if($row->{'FIDELITY'} > 2 and $row->{'QUALITY'} =! 0){
				$subnet = &_ipdiscover_find_iface($result);
				if(!$subnet){
					return(&_ipdiscover_evaluate($result, $row->{'FIDELITY'}, $row->{'QUALITY'}));
				}elsif($subnet =~ /^(\d{1,3}(?:\.\d{1,3}){3})$/){
					# The computer is elected, we have to write it in devices
					$dbh->do('INSERT INTO devices(DEVICEID, NAME, IVALUE, TVALUE, COMMENTS) VALUES(?,?,?,?,?)',{},$DeviceID,'IPDISCOVER',1,$subnet,'') or return(1);
					&_log(303,"ipdiscover") if $ENV{'OCS_OPT_LOGLEVEL'};
					return(0);
				}else{
					return(0);
				}
			}else{
				return(0);
			}
		}
	}
	


	# If needed, we remove
	if($remove){
		if(!$dbh->do('DELETE FROM devices WHERE DEVICEID='.$dbh->quote($DeviceID).' AND NAME="IPDISCOVER"')){
			return(1);
		}
		&_log(304,"ipdiscover") if $ENV{'OCS_OPT_LOGLEVEL'};
	}
	0;
}

sub _ipdiscover_read_result{

	my ($result, $subnet) = @_;
	my $mask;
	my $update_req;
	my $insert_req;
	my $request;

	my $dbh = $CURRENT_CONTEXT{"DBI_HANDLE"};
	
	if(exists($result->{CONTENT}->{IPDISCOVER})){
		my $base = $result->{CONTENT}->{NETWORKS};
		
		# Retrieve netmask
		for(@$base){
			if($_->{IPSUBNET} eq $subnet){
				$mask = $_->{IPMASK};
				last;
			}		
		}
		
		# We insert the results (MAC/IP)
		$update_req = $dbh->prepare("UPDATE netmap SET IP=?,MASK=?,NETID=?,DATE=NULL WHERE MAC=?");
		$insert_req = $dbh->prepare("INSERT INTO netmap(IP, MAC, MASK, NETID) VALUES(?,?,?,?)");
		
		$base = $result->{CONTENT}->{IPDISCOVER}->{H};
		for(@$base){
			unless($_->{I}=~/^(\d{1,3}(?:\.\d{1,3}){3})$/ and $_->{M}=~/.{2}(?::.{2}){5}/){
				&_log(305,"ipdiscover") if $ENV{'OCS_OPT_LOGLEVEL'};
				next;
			}
			$update_req->execute($_->{I}, $mask, $subnet, $_->{M});
			unless($update_req->rows){
				$insert_req->execute($_->{I}, $_->{M}, $mask, $subnet);
			}
		}
	}else{
		return(1);
	}

	# Maybe There are too much ipdiscover per subnet ?
	$request=$dbh->prepare('SELECT deviceid FROM devices WHERE TVALUE='.$dbh->quote($subnet).' AND NAME="IPDISCOVER"' );
	$request->execute();
	if($request->rows > $ENV{'OCS_OPT_IPDISCOVER'}){
		$request->finish;
		return(1);
	}
	
	return(0);
}

sub _ipdiscover_find_iface{

	my $result = shift;
	my $base = $result->{CONTENT}->{NETWORKS};
	my $dbh = $CURRENT_CONTEXT{"DBI_HANDLE"};
	
	my $request;
	my @worth;
	
	for(@$base){
		if($_->{DESCRIPTION}=~/ppp/i){
			if($_->{STATUS}!~/up/i){
				if($_->{IPMASK}!~/^(?:255\.){2}/){
					if($_->{IPSUBNET}!~/^(\d{1,3}(?:\.\d{1,3}){3})$/){
						next;
		}}}}
		# Looking for a need of ipdiscover
		$request = $dbh->prepare('SELECT deviceid FROM devices WHERE TVALUE='.$dbh->quote($_->{IPSUBNET}).' AND NAME="IPDISCOVER"' );
		$request->execute();
		if($request->rows < $ENV{'OCS_OPT_IPDISCOVER'}){
			$request->finish;
			return $_->{IPSUBNET};
		}
		$request->finish;
			
		# Looking for ipdiscover older than ipdiscover_max_value
		# and compare current computer with actual ipdiscover
	}
	return(0);
	
}

sub _ipdiscover_evaluate{

	my ($result, $fidelity, $quality) = @_;

	my $dbh = $CURRENT_CONTEXT{"DBI_HANDLE"};
	my $DeviceID = $CURRENT_CONTEXT{"DEVICEID"};

	my $request;
	my $row;
	my $time = time();
	my $max_age = $ENV{'OCS_OPT_IPDISCOVER_MAX_ALIVE'}*86400;
	
	my $over;
	my @worth;

	my $base = $result->{CONTENT}->{NETWORKS};
	for(@$base){
		if(defined($_->{SUBNET}) and $_->{SUBNET}=~/^(\d{1,3}(?:\.\d{1,3}){3})$/){

			$request = $dbh->prepare('select h.DEVICEID AS DEVICEID, h.QUALITY AS QUALITY, UNIX_TIMESTAMP(h.LASTDATE) AS LAST from hardware h,devices d where d.DEVICEID=h.DEVICEID and d.TVALUE='.$dbh->quote($_->{SUBNET}).' AND h.DEVICEID<>'.($dbh->quote($DeviceID)));
			$request->execute;

			while($row = $request->fetchrow_hashref){
				# If we find an ipdiscover that is older than IP_MAX_ALIVE, we replace it with the current
				if( (($time - $row->{'LAST'}) > $max_age) and $max_age){
					@worth = ($row->{'DEVICEID'}, $row->{'QUALITY'} );
					$over = 1;
					last;
				}
				# For the first round
				unless(@worth){
					@worth = ($row->{'DEVICEID'}, $row->{'QUALITY'} );
					next;
				}
				# Put the worth in @worth
				@worth = ( $row->{'DEVICEID'}, $row->{'QUALITY'} ) if $worth[1] < $row->{'QUALITY'};
			}

			# If not over, we compare our quality with the one of the worth on this subnet.
			# If it is better more than one, we replace it
			if(($quality < $worth[1] and ($worth[1]-$quality>1)) or $over){
				# Compare to the current and replace it if needed
				if(!$dbh->do('UPDATE devices SET DEVICEID='.($dbh->quote($DeviceID)).' where DEVICEID='.($dbh->quote($worth[0])).' AND (NAME="IPDISCOVER")')){
					return(1);
				}
				&_log(303,"ipdiscover",$over?"over":"better") if $ENV{'OCS_OPT_LOGLEVEL'};
			}
		}else{
				next;
		}
	}
}
1;