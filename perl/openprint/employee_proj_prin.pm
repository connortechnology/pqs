package openprint::employee_proj_prin;
use strict;
use Date::Calc qw(Add_Delta_Days Date_to_Days check_date );

use openprint ();

require openprint::Project;
require openprint::order;
require openprint::service;
require openprint::Equipment;
require openprint::employee_schedule;
require openprint::press_schedule;

require openprint::employee_production;
require openprint::employee_project;

require sql;
require openprint::ServiceType_Category;
require openprint::SignatureCapture;
require openprint::File;
require openprint::User_Notification;
require openprint::Operator_Role;
require openprint::Project_Service_Operator;
require openprint::CIP3_PPF;


use vars qw( $r $log $dbh %variable %param %session %config );
*r = \$openprint::r;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;

sub init {
	openprint::employee_production::load_press_completion( $log, $dbh, \%variable, $variable{ProjectIndex} );
}

sub _production_feedback {
	openprint::employee_project::_production_feedback( );
}

sub _previews {
	return if ! $param{action};

	my $Project = new openprint::Project( $param{ProjectIndex} );
	$variable{ServiceIndex} = $param{ServiceIndex};

	require openprint::CIP3_PPF;
	my $PPF = new openprint::CIP3_PPF( $param{ppf_id} );

	if ( $param{action} eq 'SendPPF' ) {
		my $Equipment;
		foreach my $sig_id ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
			if ( $$sig_specs{SignatureIndex} == $$PPF{signature} ) {
				my @Equipment = openprint::Equipment->find(
						strid=>($$sig_specs{UsePress} ? $$sig_specs{UsePress} : $$sig_specs{'ddmPress'.$Project->ordered_quantity_index()})
						);
				if ( @Equipment ) {
					$Equipment = $Equipment[0];
					last;
				}
			} # end if
		} # end foreach
		if ( ! $Equipment ) {
			$log->debug('Looking it up from Schedule');
			my @rows = openprint::press_schedule->find(project_id=>$param{ProjectIndex},service_id=>$param{ServiceIndex});
			if ( @rows == 1 ) {
				$Equipment = new openprint::Equipment($rows[0]{equipment_id});
			}
		} # end if
		if ( ! $Equipment ) {
			$log->error("Unable to load equipment.  No PPF for you for signature $$PPF{signature}.");
		} else {
			$PPF->send_ppf( $Equipment );
		} # end if
	} elsif ( $param{action} eq 'DeletePPF' ) {
		$variable{error} .= $PPF->delete();
	} else {
		$log->error("Unknown action $param{action} in _previews");
	} # end if
	return;
} # end sub _previews

1;
__END__
