package openprint::logs;

use strict;

require sql;

use openprint::Log;
use openprint::pagination;

use openprint;
use vars qw( %variable %session %param %config $log $dbh );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;

sub get_log_actions {
	my $user_id = $openprint::session{'user_id'};
	my $sql;
	my $counter;
	my $retVal;

	my @sql_results;
	my @results;

	$sql = qq~
		SELECT 
		   id,
		   name,
		   description 
      FROM 
			log_actions 
      ORDER BY name
	~;

	@sql_results = sql::execute( $openprint::log, $openprint::dbh, $sql, );

	while ( @sql_results ) {
	   my ($id, $name, $description) = splice(@sql_results, 0, 3,);
		$retVal .= "<span class=\"logAction\"><input type=\"checkbox\" name=\"log_actions\" id=\"log_action-$id\" value=\"$id\" onclick =\"clickLogAction(this);\" /><label class=\"radio\" for=\"log_action-$id\">$name</label></span>";
	} # end while

	return $retVal;
}

sub insertLogRecord {
	my ( $action_type_id, $note, $user_id, $company_id ) = @_;

	$user_id = $openprint::session{user_id} if ! $user_id;
	$company_id = $openprint::session{company_id} if ! $company_id;
	return if ! $user_id;

	if(!defined($action_type_id) || !($action_type_id > 0)) {
	   $action_type_id = 1;
	}
	
	my $Log = new openprint::Log();
	$Log->save({
		'action_id'	=>	$action_type_id, 
		'user_id'		=>	$user_id, 
		'company_id'	=>	$company_id,
		'ip_address'	=>	$ENV{HTTP_X_FORWARDED_FOR} ? $ENV{HTTP_X_FORWARDED_FOR} : $ENV{REMOTE_ADDR}, 
		'url'			=>	$ENV{SERVER_NAME} . $ENV{REQUEST_URI}, 
		'note'			=>	$note,
	});
	
	return 1;
}

sub index {
  if ($param{action}) {
    if ($param{action} eq 'create') {
      $log->error(Data::Dumper::Dumper(\%param));
    }
  }
}

1;
__END__
