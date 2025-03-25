#!/usr/bin/perl

# Make sure we can get access to the perl modules
use lib "/etc/apache2/lib/perl/";

require sql;
require logger;
require misc;
require ssi;
require configuration;

use openprint;
use vars qw( %variable $log $dbh %config );
*variable = \%openprint::variable;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*config = \%openprint::config;

use openprint::Equipment;
use openprint::InstantGate;

use strict;

$log = logger->new();
$log->{level} = "warn";
my %sql_server;

$dbh = sql::open_sql($log, 
		'database' => 'point-one',
		'driver'   => 'Pg',
		'host'     => '',
		'login'    => 'point-one',
		'password' => 'point-one',
		);

configuration::init_cache( $log, $dbh );

foreach my $Equipment ( openprint::Equipment->find( 'instantgate_enabled'=>'true' ) ) {
	next if ! $Equipment->cost_center();
	my $filename = $config{'InstantGateJobFilesLocalPath'}.'/'.$Equipment->cost_center().'.txt';
	if ( ! open( FH, "<$filename" ) ) {
		$log->warn("Unable to open InstantGate Report File: $filename : $!");
		next;
	} # end if
	my $ac = sql::start_transaction( $dbh );
	while ( <FH> ) {
		openprint::InstantGate::ParseRecord( $Equipment, split "\t" );
	} # end while
	sql::start_transaction( $dbh, $ac );
	close FH;
} # end foreach

$dbh->disconnect();

1;

__END__
