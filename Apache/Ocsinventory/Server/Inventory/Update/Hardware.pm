###############################################################################
## OCSINVENTORY-NG 
## Copyleft Pascal DANEK 2008
## Web : http://ocsinventory.sourceforge.net
##
## This code is open source and may be copied and modified as long as the source
## code is always made freely available.
## Please refer to the General Public Licence http://www.gnu.org/ or Licence.txt
################################################################################
package Apache::Ocsinventory::Server::Inventory::Update::Hardware;

use strict;

require Exporter;

our @ISA = qw /Exporter/;

our @EXPORT = qw / _hardware /;

use Apache::Ocsinventory::Server::Constants;
use Apache::Ocsinventory::Server::System qw / :server /;

sub _hardware{
  my $result = $Apache::Ocsinventory::CURRENT_CONTEXT{'XML_ENTRY'};
  my $base = $result->{CONTENT}->{HARDWARE};
  my $ua = $Apache::Ocsinventory::CURRENT_CONTEXT{'USER_AGENT'};
  my $deviceId = $Apache::Ocsinventory::CURRENT_CONTEXT{'DATABASE_ID'};
  my $dbh = $Apache::Ocsinventory::CURRENT_CONTEXT{'DBI_HANDLE'};
  # We replace all data but quality and fidelity. The last come becomes the last date.
  my $userid = '';	
  $userid = "USERID=".$dbh->quote($base->{USERID})."," if( $base->{USERID}!~/(system|localsystem)/i );

  $dbh->do("UPDATE hardware SET USERAGENT=".$dbh->quote($ua).", 
	LASTDATE=NOW(), 
	LASTCOME=NOW(),
	CHECKSUM=(".(defined($base->{CHECKSUM})?$base->{CHECKSUM}:CHECKSUM_MAX_VALUE)."|CHECKSUM|1),
	NAME=".$dbh->quote($base->{NAME}).", 
	WORKGROUP=".$dbh->quote($base->{WORKGROUP}).",
	USERDOMAIN=".$dbh->quote($base->{USERDOMAIN}).",
	OSNAME=".$dbh->quote($base->{OSNAME}).",
	OSVERSION=".$dbh->quote($base->{OSVERSION}).",
	OSCOMMENTS=".$dbh->quote($base->{OSCOMMENTS}).",
	PROCESSORT=".$dbh->quote($base->{PROCESSORT}).", 
	PROCESSORS=".(defined($base->{PROCESSORS})?$base->{PROCESSORS}:0).", 
	PROCESSORN=".(defined($base->{PROCESSORN})?$base->{PROCESSORN}:0).", 
	MEMORY=".(defined($base->{MEMORY})?$base->{MEMORY}:0).",
	SWAP=".(defined($base->{SWAP})?$base->{SWAP}:0).",
	IPADDR=".$dbh->quote($base->{IPADDR}).",
	ETIME=".$dbh->quote($base->{ETIME}).",
	$userid
	TYPE=".(defined($base->{TYPE})?$base->{TYPE}:0).",
	DESCRIPTION=".$dbh->quote($base->{DESCRIPTION}).",
	WINCOMPANY=".$dbh->quote($base->{WINCOMPANY}).",
	WINOWNER=".$dbh->quote($base->{WINOWNER}).",
	WINPRODID=".$dbh->quote($base->{WINPRODID}).",
	WINPRODKEY=".$dbh->quote($base->{WINPRODKEY})."
	 WHERE ID=".$deviceId)
  or return(1);
	
  $dbh->commit unless $ENV{'OCS_OPT_INVENTORY_TRANSACTION'};
  0;
}

1;