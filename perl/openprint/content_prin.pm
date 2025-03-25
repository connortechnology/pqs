use strict;
package openprint::content_prin;

require openprint::main_project;
require openprint::Project;
require openprint::ProjectType;
require openprint::ProjectType_Default;
use openprint ();
use vars qw( $log $dbh %variable %param %session );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*param = \%openprint::param;
*variable = \%openprint::variable;
*session = \%openprint::session;

sub _breakdown {
	openprint::main_project::view( $param{'project_id'} ) if $param{'project_id'};
}

sub load_simple {
	$param{'project_id'} =~ s/\D//g;

	$variable{'Project'} = new openprint::Project( $param{'project_id'} );
	if ( $variable{'Project'}->id() ) {
		$variable{'ProjectType'} = $variable{'Project'}->Type();
		my $services = $variable{'Project'}->services();
		if ( $$services{'UPS'} ) {
			$variable{'UPSShipping'} = 'Y';
			foreach my $service_id ( @{$$services{'UPS'}} ) {
				my $service_specs = openprint::service::get_specs_ref( $variable{'Project'}, $service_id );
				@variable{'ToPostalCode','ToCountry'} = @$service_specs{'ToPostalCode','ToCountry'};
				last;
			} # end foreach
		} # end if
	} else {
		$param{'projecttype_id'} = openprint::ProjectType->transform( 'id', $param{projecttype_id} );
		$param{'ProjectType'} =~ s/\s//g;
		if ( $param{'projecttype_id'} ) {
			$variable{'ProjectType'} = new openprint::ProjectType( $param{'projecttype_id'} );
		} elsif ( $param{'ProjectType'} ) {
			$variable{'ProjectType'} = openprint::ProjectType->find_one( 'name'=>$param{'ProjectType'} );
			if ( ! $variable{'ProjectType'} ) {
				$variable{'error'} .= "Invalid Project Type: $param{ProjectType}";
			} # end if
		
		} # end if
	} # end if
	if ( ! $variable{'ProjectType'} ) {
		$variable{'ProjectType'} = new openprint::ProjectType();
	}
	if ( ! $variable{'ToCountry'} ) {
		if ( $session{'company_id'} ) {
			$variable{'ToCountry'} = new openprint::Company( $session{'company_id'} )->country();
		} 
		if ( ! $variable{'ToCountry'} ) {	
			$variable{'ToCountry'} = $session{'Country'};
		} # end if
	} # end if
	if ( ! $variable{'ToPostalCode'} ) {
		if ( $session{'company_id'} ) {
			$variable{'ToPostalCode'} = new openprint::Company( $session{'company_id'} )->postalcode();
		} # end if
	} # end if

	foreach ( openprint::ProjectType_Default->find( projecttype_id => undef ) ) {
		$variable{$_->name()} = $_->value();
	} # end foreach
	my $services = $variable{'Project'}->services();
	if ( $$services{''} ) {
		my $printing_specs = openprint::service::get_specs_ref( $variable{'Project'}, $$services{''}[0] );
		foreach my $k ( 'txtFinalWidth','txtFinalHeight','txtWidth','txtHeight','ddmStockFinish','ddmStockBrand','ddmStockWeight','ddmStockColour','ddmStockSheetSize' ) {
			$variable{$k} = $$printing_specs{$k};
		} # end foreach
	} elsif ( $variable{'ProjectType'}->id() ) {
		# Load defaults
		foreach ( openprint::ProjectType_Default->find('projecttype_id'=> $variable{'ProjectType'}->id() ) ) {
            $variable{$_->name()} = $_->value();
        } # end foreach
	} # end if

	# So that default services start turned on
	foreach my $ServiceType ( $variable{'ProjectType'}->required_ServiceTypes() ) {
		$variable{$ServiceType->name()} = 'Y';
	} # end foreach ServiceType

} # end sub load_simple

sub Signature {
	load_simple();
} # end sub Signature

sub prin_multi {
	load_simple();
} # end sub prin_multi
sub envelopes {
	load_simple();
} # end sub envelopes
sub presentationfolders {
	load_simple();
} # end sub presentationfolders
sub no_printing_required {
	load_simple();
} # end sub no_printing_required

sub banners {
	load_simple();
	$variable{'Redirect'} = '/content/'.$variable{'ProjectType'}->url();
} # end sub banners

sub ChannelLetters {
	load_simple();
}

1;
__END__
