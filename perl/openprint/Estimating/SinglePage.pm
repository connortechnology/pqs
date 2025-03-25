# Copyright (C) 2007 Isaac Connor <isaac@connortechnology.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA

package openprint::Estimating::SinglePage;

use POSIX qw{ ceil };
use strict;

require openprint::Estimating::Printing;
require openprint::service;
require sets;

use constant DEBUG => 0;

my %variables = (
	'ddmProjectSize'=>['save','output'],
	'txtFinalWidth'=>['save'],'txtFinalHeight'=>['save'], 
	'txtWidth'=>['save','output'],'txtHeight'=>['save','output'],
	'PrintingType'=>['save'],'rdbTemplateType'=>['save'],
	'help'=>['output'],'alert'=>['save','output'],
	'ProjectIndex'=>[], 'ServiceIndex'=>[], 'ServiceType'=>[],
	'txtPrice1'=>['save'],
	'txtPrice2'=>['save'],
	'txtPrice3'=>['save'],
);

sub variables {
	my @v;
	foreach my $k ( keys %variables ) {
		push @v, $k if sets::isin( 'save', $variables{$k} );
	} # end foreach;
	return @v;
} # end sub variables

sub no_outputs {
    my @v;
    foreach my $k ( keys %variables ) {
        push @v, $k, if ! sets::isin( 'output', $variables{$k} );
    } # end foreach;
    return @v;
}


sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;
	my $Project = new openprint::Project( $project_index );
	if ( ! $Project->signatures() ) {
    $openprint::log->debug('No signatures in SinglePage::calc so add one:'.$Project->to_string()) if DEBUG;
		$Project->add_signature( );
	} # end if
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		if ( $$specs{'txtPrice'.$qty_index} ) {
			$$specs{'txtPrice'.$qty_index} = undef;
		} # end if
	}# end foreach

	return $$specs{Status} = 'calculated';
} # end sub calc

sub calculate_signatures {
	shift @_ if $_[0] eq 'openprint::Estimating::SinglePage::calculate_signatures';
	my $Project = $_[0];

	my $status = 'calculated';
$openprint::log->debug("****************************************************************Starting SinglePage::calculate_signatures");
	my $services = $Project->services();

	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );

	my @signatures = $Project->signatures();
$openprint::log->debug( "Signature: @signatures");

	# If we have a specified printing type, then .... if any of the sigs aren't of the same printing type is this even neccessary? 
	for ( my $i = 0; $i < @signatures; $i += 1 ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $signatures[$i] );

		if ( $$printing_specs{PrintingType} ) {
			if ( 
				 ( $Project->quantity1() and ( $$sig_specs{PrintingType1} ne $$printing_specs{PrintingType} ) )
				 or ( $Project->quantity2() and ( $$sig_specs{PrintingType2} ne $$printing_specs{PrintingType} ) )
					or ( $Project->quantity3() and ( $$sig_specs{PrintingType3} ne $$printing_specs{PrintingType}  ) )
) {
# delete any similar signs
				#$log->debug("Getting rid of extra sigs");
				for ( my $j = $i+1; $j < @signatures; $j += 1 ) {
					my $specs2 = openprint::service::get_specs_ref( $Project, $signatures[$j] );
					if ( openprint::Estimating::Printing::compare_signatures( $Project, $sig_specs, $specs2 ) ) {
#$openprint::log->warn('Deleting due to incorrect printing type');
						openprint::print_project::delete_service( $Project, $signatures[$j] );
						splice @signatures, $j, 1;
						$j-=1;
					} # end if
				} # end for
			} # end if any have a different PrintingType
		} # end if PrintingType
	} # end for

	my @sigs = sort $Project->signatures( );
	my $ss_id = shift @sigs;

	my $sig_specs = openprint::service::internal_calc( $openprint::log, $openprint::dbh, \%openprint::variable, $$Project{id}, $ss_id, 'Printing' );
# If we couldn't calculate, then delete all the other printing types and retry.
	if ( $$sig_specs{Status} eq 'calculated' ) {
		$status = $$sig_specs{Status};
		# Successfully calculated the first sig
		# In sig_specs should be an array of Impositions to apply to other signatures, so let's add/delete/apply

		while ( 
			( $$sig_specs{'Additional Impositions1'} and @{$$sig_specs{'Additional Impositions1'}} ) or
			( $$sig_specs{'Additional Impositions2'} and @{$$sig_specs{'Additional Impositions2'}} ) or
			( $$sig_specs{'Additional Impositions3'} and @{$$sig_specs{'Additional Impositions3'}} ) ) {
			if ( ! @sigs ) {
				push @sigs, $Project->copy_signature( $sig_specs, {
					'chkOverrideImposition1' => '',
					'chkOverrideImposition2' => '',
					'chkOverrideImposition3' => '',
					'chkOverridePageQuantity1' => '',
					'chkOverridePageQuantity2' => '',
					'chkOverridePageQuantity3' => '',
					'chkOverridePress1' => '',
					'chkOverridePress2' => '',
					'chkOverridePress3' => '',
					'chkOverrideRunStyle1' => '',
					'chkOverrideRunStyle2' => '',
					'chkOverrideRunStyle3' => '',
					'chkOverrideSheetSize1' => '',
					'chkOverrideSheetSize2' => '',
					'chkOverrideSheetSize3' => '',
				},'calculated' );
			} # endif
			$openprint::log->debug("Saving additional impositions1 " . @{$$sig_specs{'Additional Impositions1'}} ) if $$sig_specs{'Additional Impositions1'} and @{$$sig_specs{'Additional Impositions1'}};
			$openprint::log->debug("Saving additional impositions2 " . @{$$sig_specs{'Additional Impositions2'}} ) if $$sig_specs{'Additional Impositions2'} and @{$$sig_specs{'Additional Impositions2'}};
			$openprint::log->debug("Saving additional impositions3 " . @{$$sig_specs{'Additional Impositions3'}} ) if $$sig_specs{'Additional Impositions3'} and @{$$sig_specs{'Additional Impositions3'}};

			my $a_ss_id = shift @sigs;
			my $new_sig_specs = openprint::service::get_specs_ref( $Project, $a_ss_id );
			my %specs = %{$new_sig_specs};

			foreach my $qty_index ( $Project->quantity_indexes() ) {
				my $Imposition;

				if ( ! ( $$sig_specs{'Additional Impositions'.$qty_index} and @{$$sig_specs{'Additional Impositions'.$qty_index}} ) ) {
					$specs{'ddmPress'.$qty_index} = '' if $specs{'chkOverridePress'.$qty_index} ne 'Y';
					$specs{'PageQuantity'.$qty_index} = '' if $specs{'chkOverridePageQuantity'.$qty_index} ne 'Y';
					$specs{'txtImposition'.$qty_index} = '';
					$specs{'StockType'.$qty_index} = '';
					$specs{'StockWidth'.$qty_index} = '';
					$specs{'StockHeight'.$qty_index} = '';
					$specs{'txtPressSheetQty'.$qty_index} = 0;
					$specs{'hdnNetSheetCount'.$qty_index} = 0;
					$specs{'StockQuantity'.$qty_index} = 0;
					if ( $specs{'OverridePrice'.$qty_index} ne 'Y' ) {
						$specs{'txtPrice'.$qty_index} = sprintf($openprint::config{ProjectMoneyFormat}, 0 );
					} # end if
					$specs{'txtUnitPrice'.$qty_index} = sprintf($openprint::config{UnitPriceFormat}, 0 );
					$Imposition = new openprint::Imposition();
					$$Imposition{Paper} = new openprint::Paper();
				} else {
					$Imposition = shift @{$$sig_specs{'Additional Impositions'.$qty_index}};
				} # end if

				if ( ref $Imposition ne 'openprint::Imposition' ) {
					cluck( "Bad Imposition! $Imposition" );
					$status = 'uncalculated';
					next;
				} # end if

				my $price = $$Imposition{price};

				$Imposition->save( \%specs, $qty_index );
				openprint::Estimating::Printing::save_price( $Project, \%specs, $price, $Imposition, $qty_index );
				$specs{'hdnBreakdown'.$qty_index} = openprint::Estimating::Printing::breakdown( $price, \%specs );

			} # end foreach qty_index

			$Project->lock();
			sql::update( undef, undef, 'tbl_Project_Contents', ['lngProjectIndex=? AND lngServiceIndex=?', $$Project{id}, $a_ss_id], 'strStatus', $status );

			foreach my $key ( openprint::Estimating::Printing::variables( $$Project{id}, $a_ss_id, $new_sig_specs, \%specs ) ) {
				openprint::service::insert_service_spec( undef, undef, $$Project{id}, $a_ss_id, $key, $specs{$key} );
			} # end foreach
			$Project->unlock();

		} # end while Additional Imposition

# Clean up any leftovers
		while ( @sigs and my $ss_id = shift @sigs ) {
			my $Service = $Project->Service( $ss_id );
			$Service->delete();
			@signatures = sets::exclude( [ $ss_id ], \@signatures );
		} # end while sigs

	} else {
		$openprint::log->debug("unknown status: $$sig_specs{Status} alert: $$sig_specs{alert}");
		$status = $$sig_specs{Status};
	} # end if

	return $status;
} # end sub calculate_signatures

# Returns the # of needed remaining spreads... 
sub status {
	my ( $project_index, $printing_specs, $qty_index ) = @_;

	my $Project = new openprint::Project( $project_index );
	my @sigs = $Project->signatures();
	return 'uncalculated' if ! @sigs;
	
	my $sig_specs = openprint::service::get_specs_ref( $Project, $sigs[0] );
	my $needed_versions = $$sig_specs{Versions};
	if ( $needed_versions ) {
		my $versions = 0;
		foreach my $sig_id ( @sigs ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
			$versions += $$sig_specs{"Versions$qty_index"};
		} # end foreach
		if ( $versions < $needed_versions ) {
			return 'uncalculated';
		} # end if
	} # end if
	return;
} # end sub status

sub save {
} # end sub save
        
1;
__END__
