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

use strict;
use warnings;
package openprint::Estimating::Skids;
use POSIX qw(ceil);

require openprint::service;

use constant DEBUG=>0;

my %variables = (
	'txtFinalWidth'=>['output'],'txtFinalHeight'=>['output'],
	item_type	=>	['save','output'], item_type_lock=>['save'],
	'txtPackageQuantity1' => ['save','output'], 'txtPackageQuantity2' => ['save','output'], 'txtPackageQuantity3' => ['save','output'],
	'txtUnitPrice1' => ['output'], 'txtUnitPrice2' => ['output'], 'txtUnitPrice3' => ['output'],
	'MPrice1' => ['save','output'], 'MPrice2' => ['save','output'], 'MPrice3' => ['save','output'],
	'txtPrice1' => ['save','output'], 'txtPrice2' => ['save','output'], 'txtPrice3' => ['save','output'],
	'Markup1'=>['save'], 'Markup2'=>['save'], 'Markup3'=>['save'],
	'OverridePrice1'=>['save'], 'OverridePrice2'=>['save'], 'OverridePrice3'=>['save'],
	'txtFinishedCalliper' => ['save','output'], 'chkOverrideFinishedCalliper' => ['save'],
	'txtFinishedWeight' => ['save','output'],
	'ddmPackageType1' => ['save','output'], 'OverridePackageType1'=>['save'],
	'ddmPackageType2' => ['save','output'], 'OverridePackageType2'=>['save'],
	'ddmPackageType3' => ['save','output'], 'OverridePackageType3'=>['save'],
	'items_per_package' => ['save'],
	'txtItemsPerPackage1' => ['save','output'], 'txtItemsPerPackage2' => ['save','output'], 'txtItemsPerPackage3' => ['save','output'], 
	'OverrideItemsPerPackage1'=>['save'], 'OverrideItemsPerPackage2'=>['save'], 'OverrideItemsPerPackage3'=>['save'],
	'txtPackageWeight1' => ['save','output'], 'txtPackageWeight2' => ['save','output'], 'txtPackageWeight3' => ['save','output'],
	'totalWeight1' => ['save','output'],'totalWeight2' => ['save','output'],'totalWeight3' => ['save','output'],
	'alert'=>['save','output'], 
	'hdnBreakdown1'=>['output'], 'hdnBreakdown2'=>['output'], 'hdnBreakdown3'=>['output'],

);

sub variables {
	my @v;
	foreach my $k ( keys %variables ) {
		push @v, $k, if sets::isin( 'save', $variables{$k} );
	} # end foreach;
	return @v;
}

sub has_overrides {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

	my @v;
	if ( $qty_index ) {
		push @v, map { ( $$specs{$_.$qty_index} and $$specs{$_.$qty_index} ne 'N' ) ? $_ : () } (
				'OverridePrice','OverridePackageType','OverrideItemsPerPackage',
				);
	} # end if

	return @v;
} # end sub has_overrides

sub outputs {
	my @v;
	foreach my $k ( keys %variables ) {
		push @v, $k, if sets::isin( 'output', $variables{$k} );
	} # end foreach;
	return @v;
}

sub no_outputs {
	my @v;
	foreach my $k ( keys %variables ) {
		push @v, $k, if ! sets::isin( 'output', $variables{$k} );
	} # end foreach;
	return @v;
}

sub neccessary {
	my ( $Project, $type ) = @_;
# type is actually category name, not material type

	if ( $type eq 'BulkSkids' ) {
		my $finished_weight = $Project->finished_weight();
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			if ( $finished_weight * $$Project{'quantity'.$qty_index} > 1500 ) {
				return 1;
			} # end if
		} # end freach qty_index
	} elsif ( $type eq 'PlainCartons' ) {
		
	} # end if
	return 0;
} # end sub neccessary 

# This doesn't use service_index for a reason.  THe idea is that we can call this on some specs and see what would happen, without ever actually adding the service.
sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	$$specs{Status} = 'calculated';
  $$specs{alert} = '';

	$log->debug("********************** START OF CALC SKIDS type:($$specs{ServiceType})**********************") if DEBUG;
	my $Project = new openprint::Project($project_index);
	my $services = $Project->services();
	my $ServiceType = $Project->ServiceType($service_index);

	my $makeReady = openprint::service::get_price( $ServiceType->name().'MakeReady', undef, undef );
	$makeReady = 0 if ! defined $makeReady;
	my $serviceCharge = openprint::service::get_price( $ServiceType->name(), undef, undef );
	$serviceCharge = 0 if ! defined $serviceCharge;
	my $packingCharge = openprint::service::get_price( $ServiceType->name().'Packing', undef, undef );
	$packingCharge = 0 if !defined $packingCharge;

	my @signatures = $Project->signatures();

	my $printing_specs;
	if ($Project->Type()->type() ne 'MultiPage') {
		$printing_specs = openprint::service::get_specs_ref($Project, $$services{Signature}[0]);
	} else {
		$printing_specs = openprint::service::get_specs_ref($Project, $$services{''}[0]);
	} # end if

	# Flat sheets or finished product?
  if (!$$specs{item_type} or !$$specs{item_type_lock}) {
    if (!$$services{Cutting} and !$$services{Folding} and !$$services{DieCutting}) {
      $$specs{item_type} = 'FlatSheets';
    } else {
      my @bindery_services = map { $$services{$$_{name}} ? $$services{$$_{name}} : () } openprint::Service->find(category=>'Bindery');
      $openprint::log->debug("Bindery Services: @bindery_services");
      if (!@bindery_services) {
        $$specs{item_type} = 'FlatSheets';
      } else {
        $$specs{item_type} = 'FinishedProduct';
      }
    }
	}
  $openprint::log->debug("Item type $$specs{item_type}") if DEBUG;

	@$specs{'txtFinalWidth','txtFinalHeight'} = @$printing_specs{'txtFinalWidth','txtFinalHeight'};
	if ( ! ( $$specs{txtFinalWidth} and $$specs{txtFinalHeight} ) ) {
		@$specs{'txtFinalWidth','txtFinalHeight'} = @$printing_specs{'txtWidth','txtHeight'};
	} # end if
	if ( ! ( $$specs{txtFinalWidth} and $$specs{txtFinalHeight} ) ) {
		$$specs{alert} .= 'Dimensions of project are not known. Please enter them.';
		return $$specs{Status} = 'uncalculated';
	} # end if
	if ((!$$specs{chkOverrideFinishedCalliper}) or ($$specs{chkOverrideFinishedCalliper} ne 'Y')) {
		$$specs{txtFinishedCalliper} = $Project->calliper();
	} # end if
	if (!(1*$$specs{txtFinishedCalliper})) {
		$$specs{alert} .= 'Unable to calculate the calliper of the project.  Please recalculate printing services.';
		return $$specs{Status} = 'uncalculated';
	} # end if
	$$specs{txtFinishedWeight} = $Project->finished_weight( 1 );
	if ( ! $$specs{txtFinishedWeight} ) {
		$$specs{alert} .= 'Unable to calculate the weight of the project.  Please recalculate printing services.';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my @AllMaterials = openprint::Material->find(category=>$ServiceType->name());
	$$specs{alert} .= 'There are no materials for '.$ServiceType->name().'<br/>' if !@AllMaterials;
	
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"Markup$qty_index"};
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtPrice$qty_index"};
		$$specs{"txtQuantity$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtQuantity$qty_index"};
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		if ( ! $$specs{"txtQuantity$qty_index"} > 0 ) {
			$log->error("Empty txtQuantity for QTY $qty_index");
			$$specs{alert} .= "Please enter the # of items to pack for quantity $qty_index.<br/>";
			next;
		} # end if
		$$specs{'hdnBreakdown'.$qty_index} = '';
		$$specs{'txtItemsPerPackage'.$qty_index} = '' if (!$$specs{'OverrideItemsPerPackage'.$qty_index}) or ($$specs{'OverrideItemsPerPackage'.$qty_index} ne 'Y');

		my @Materials;
		if ($$specs{'OverridePackageType'.$qty_index} and ($$specs{'OverridePackageType'.$qty_index} eq 'Y')) {
			my $Material = new openprint::Material( $$specs{'ddmPackageType'.$qty_index} );
			@Materials = ( $Material );
		} else {
			@Materials = @AllMaterials;
			$$specs{'ddmPackageType'.$qty_index} = '';
		} # end if

		local *calc_signature = sub {
			my ($sig_specs, $item_qty, $item_width, $item_height, $item_calliper, $item_weight, $imposition, $item_name) = @_;
			my $results = {
				breakdown => '',
				material_price => 0,
			};
			my $best_price = undef;

			foreach my $Material (@Materials) {
				my ($items_by_size, $items_per_package) = (0, 0);
				my $width = $Material->specification('Width');
				my $height = $Material->specification('Height');
				my $depth = $Material->specification('Depth');

				$$results{breakdown} .= '<fieldset><legend>'.$Material->name().':'.$width.'x'.$height.'x'.$depth.'</legend>';

# Make sure it's not too heavy
        my $max_weight = $Material->specification('Maximum Weight');
				my $items_by_weight = 0;
        if ($max_weight) {
          $items_by_weight = $item_weight ? int($max_weight / $item_weight) : 0;
          $$results{breakdown} .= sprintf('Items by weight: Max %d / item weight %.3f = %d per package<br/>',
            $Material->specification('Maximum Weight'), $item_weight, $items_by_weight );
        } else {
          $$results{breakdown} .= 'Please consider setting a Maximum Weight setting on this carton.<br/>';
        }

				if ($width and $height and $depth) {
					my $setup = openprint::imposition::fit($item_width, $item_height, $width, $height);

					if ($$setup{imposition}) { # Fits flat
						if ($$specs{item_type} eq 'FlatSheets') {
			
							# It is unlikely to do more than 2out on a skid
							my $imp = ($$setup{imposition} > 2) ? 2 : $$setup{imposition};
							$items_by_size = int($depth/$item_calliper) * $imp;
							$$results{breakdown} .= sprintf('%ss by size: %sx%s on %sx%s=%dout %s/%s = %d high %dout sheets = %d per package<br/>',
									$item_name, $item_width, $item_height, $width, $height, $imp, $depth, $item_calliper, int($depth/$item_calliper), $imp, $items_by_size*$imp);
						} else {
							$items_by_size = int($depth/$item_calliper) * $$setup{imposition};
							$$results{breakdown} .= sprintf('%ss by size: %sx%s on %sx%s=%dout %s/%s = %d high * %dout = %d per package<br/>',
									$item_name, $item_width, $item_height, $width, $height, $$setup{imposition}, $depth, $item_calliper, int($depth/$item_calliper), $$setup{imposition}, $items_by_size);
						}
					} else {
# Try Rolling
						if ($width == $height and $depth >= $item_width) {
							$$results{breakdown} .= sprintf('Rolling %sx%s on %s<br/>', $item_width, $item_height, $depth);
# L = pi * N * (D+d)/2 where N=(D-d)/(2*t)
							my $l = 3.14 * ( ( $width-1 ) / (2 * $item_calliper) ) * ( $width + 1 )/2;
							$$results{breakdown} .= sprintf('Max Length: %d<br/>', $l);
							$items_by_size = int($l/$item_height);
						} elsif ($width == $height and $depth >= $item_height) {
							$$results{breakdown} .= sprintf('Rolling %sx%s on %s<br/>', $item_width, $item_height, $depth);
# L = pi * N * (D+d)/2 where N=(D-d)/(2*t)
							my $l = 3.14 * ( ( $height-1 ) / (2 * $item_calliper) ) * ( $height + 1 )/2;
							$$results{breakdown} .= sprintf('Max Length: %d<br/>', $l);
							$items_by_size = int($l/$item_width);
						} else {
							$$results{breakdown} .= 'Doesn\'t fit and item can\'t be rolled<br/>';

						} # end if
					} # end if fits

					# Make sure it's not too heavy
					$items_per_package = ( $items_by_size and ($items_by_size > $items_by_weight) ) ? $items_by_weight : $items_by_size;
				} else {
					$items_per_package = $items_by_weight;
# Have to make sure to limit by height as well.
					if ($depth and 0) {
						my $items_by_depth = int($depth/$item_calliper);
						if ( $items_by_depth < $items_by_weight ) {
							$$results{breakdown} .= sprintf('Items by height: %s/%s = %d<br/>',
									$depth, $item_calliper, $items_by_depth);
							$items_per_package = $items_by_depth;
						}
					}
				} # end if
				if (($$specs{item_type} ne 'FlatSheets') and $$sig_specs{Versions}) {
					my $versions_per_package = int( $item_qty / $$sig_specs{Versions} );
					$openprint::log->debug("Per package due to versions: $item_qty / $$sig_specs{Versions} = $versions_per_package");
					if ( $versions_per_package < $items_per_package ) {
						$items_per_package = $versions_per_package;
					} # end if
				} # end if

				if ($$specs{items_per_package}) {
					if ($$specs{items_per_package} > $items_per_package) {
						$$results{alert} = 'Can\'t fit that many.<br/>';
						next;
					}
					$items_per_package = $$specs{items_per_package};
				} # end if

				if ($$specs{'OverrideItemsPerPackage'.$qty_index} and ($$specs{'OverrideItemsPerPackage'.$qty_index} eq 'Y')) {
					if ($items_per_package < $$specs{'txtItemsPerPackage'.$qty_index}) {
						$$results{breakdown} .= 'Can\'t fit '.$$specs{'txtItemsPerPackage'.$qty_index}.' in this package.<br/>';
						next;
					}
					$items_per_package = int $$specs{'txtItemsPerPackage'.$qty_index};
				} # end if

				if (!$items_per_package) {
					$$results{breakdown} .= '</fieldset>';
					next;
				} # end if

				my $package_qty = ceil($item_qty/$items_per_package);
				my $package_weight = $items_per_package * $item_weight;
				my $total_weight =
					(int($item_qty/$items_per_package) * $package_weight)
					+ (($item_qty % $items_per_package) * $item_weight);
				$$results{breakdown} .= sprintf('Items per: %d, %d packages, max weight %dlbs, total weight %dlbs<br/>',
						$items_per_package, $package_qty, $package_weight, $total_weight);

				my %MaterialPrice = $Material->get_price($package_qty, undef);
				my $compare_price = $package_qty * $MaterialPrice{Price};

				if ((!defined($best_price)) or ($compare_price < $best_price)) {
					$best_price = $compare_price;
					@$results{'material_id','items_per_package','package_qty','package_weight','total_weight','material_price', 'material_total'} =
						($Material->id(), $items_per_package, $package_qty, $package_weight, $total_weight, $MaterialPrice{Price}, $MaterialPrice{Price}*$package_qty);
				} # end if
				$$results{breakdown} .= sprintf(
						'MakeReady: %.2f, Packing Charge: %.2f: Service Charge: %.2f, Material Charge: %.2f<br/></fieldset>',
						$makeReady, $packingCharge, $serviceCharge, $MaterialPrice{Price});
			} # end foreach Material
			return $results;
		}; # end sub calc_signature

		my $m_qty = 0;
		my $package_qty = 0;
		my $package_weight = 0;
		my $total_weight = 0;
		my $material_price = 0;
		my $material_total = 0;
		my $packing_charge = 0;
		my $status = 'calculated';

		if ( $$specs{item_type} eq 'FlatSheets' ) {
			foreach my $sig_id (@signatures) {
				my $sig_specs = openprint::service::get_specs_ref($Project, $sig_id);

				my $Stock = openprint::Paper::load_from_signature($Project, $sig_specs, $qty_index);
				my $item_name;
				my $item_qty = $$sig_specs{"hdnImpressionQuantity$qty_index"};
        if (!$item_qty) {
					$$specs{alert} .= 'Unable to load impression count!<br/>';
          next;
        }
				my $imposition = new openprint::Imposition();
				$imposition->load($sig_specs, $qty_index, $Project);
				my ($item_width, $item_height, $item_calliper, $item_weight ) = (
						$imposition->sheet_width(), $imposition->sheet_height,
						$Stock->calliper(),
						$imposition->sheet_width() * $imposition->sheet_height() * $Stock->wpsi()
						);
				if (!$item_weight) {
					$$specs{alert} .= 'Unable to load sheet weight<br/>';
				}
        $item_qty /= 2 if $imposition->sides() == 2 and $$imposition{runstyle} ne 'Web';
				$item_name = 'Flat Sheet';
				my $results = calc_signature($sig_specs, $item_qty, $item_width, $item_height, $item_calliper, $item_weight, $imposition, $item_name);
				$package_qty += $$results{package_qty};
				$material_price = $$results{material_price};
				$material_total += $$results{material_total} if $$results{material_total};
				$package_weight = $$results{package_weight};
				$total_weight += $$results{total_weight} if $$results{total_weight};
				$$specs{'hdnBreakdown'.$qty_index} .= '<fieldset><legend>Form '.$$sig_specs{SignatureIndex}.'</legend>'.
					sprintf('%d sheets size %dx%d @ %.3flbs<br/>', $item_qty, $item_width, $item_height, $item_weight).
					$$results{breakdown}.'</fieldset>';
				$status = 'uncalculated' if !$$results{package_qty};
				$$specs{'txtItemsPerPackage'.$qty_index} = $$results{items_per_package};#if $$specs{'txtItemsPerPackage'.$qty_index} > $$results{items_per_package};
				$$specs{'ddmPackageType'.$qty_index} = $$results{material_id};
			} # end foreach signature
		} else {
			my $sig_specs = openprint::service::get_specs_ref($Project, $signatures[0]);
				my ($item_width, $item_height, $item_calliper, $item_weight, $item_qty, $imposition, $item_name);
			($item_width, $item_height, $item_calliper, $item_weight) = @$specs{'txtFinalWidth','txtFinalHeight','txtFinishedCalliper','txtFinishedWeight'};
			$item_qty = $$specs{"txtQuantity$qty_index"};
			$item_qty *= $$printing_specs{Versions} if $$printing_specs{Versions};
			$item_name = 'Finished Product';
			my $results = calc_signature($sig_specs, $item_qty, $item_width, $item_height, $item_calliper, $item_weight, $imposition, $item_name);
			$$specs{'hdnBreakdown'.$qty_index} .= $$results{breakdown};
			$package_qty += $$results{package_qty};
			$material_price = $$results{material_price};
				$material_total += $$results{material_total};
			$package_weight = $$results{package_weight};
			$total_weight += $$results{total_weight};
			$$specs{'txtItemsPerPackage'.$qty_index} = $$results{items_per_package};# if $$specs{'txtItemsPerPackage'.$qty_index} > $$results{items_per_package};
			$$specs{'ddmPackageType'.$qty_index} = $$results{material_id};
		}
		$$specs{Status} = 'uncalculated' if $status eq 'uncalculated';

		$$specs{'txtPackageQuantity'.$qty_index} = $package_qty;
		$$specs{'txtPackageWeight'.$qty_index} = int($package_weight);
		$$specs{'totalWeight'.$qty_index} = int($total_weight);

		my $unitPrice = $material_price + $serviceCharge + $packingCharge;
		my $price = $makeReady + ( $package_qty * $unitPrice );
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf(
						'MakeReady: %.2f, Packing Charge: %.2f + Service Charge %.2f + Material Charge: %.2f = %.2f<br/>',
						$makeReady, $packingCharge * $package_qty, $serviceCharge * $package_qty, $material_total, $price);
		if ($Project->markup()) {
			$unitPrice *= (1+$Project->markup()/100);
			$price *= (1+$Project->markup()/100);
		}
		$$specs{"txtUnitPrice$qty_index"} = sprintf($openprint::config{UnitPriceFormat},
				Math::Round::nearest($openprint::config{UnitPriceRounding}, $unitPrice));
		$$specs{"MPrice$qty_index"} = sprintf($openprint::config{UnitPriceFormat},
				Math::Round::nearest($openprint::config{UnitPriceRounding}, $unitPrice * $m_qty));

		if ((!$$specs{'OverridePrice'.$qty_index} ) or ($$specs{'OverridePrice'.$qty_index} ne 'Y')) {
			$price *= (1+$$specs{"Markup$qty_index"}/100) if $$specs{"Markup$qty_index"};
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat},
					Math::Round::nearest($openprint::config{ProjectPriceRounding}, $price));
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf($openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"});
		} # end if
	} # end foreach qty
	$$specs{txtFinishedWeight} = sprintf('%.4f', Math::Round::nearest(0.0001, $$specs{txtFinishedWeight}));
	return $$specs{Status};
} # end sub calc

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

}

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	my $package = 'skid';
	if ( $$specs{ServiceType} and ($$specs{ServiceType} eq 'Gaylords')) {
		$package = 'gaylord';
	}
	my $summary;

	if ($qty_index) {
		my $services = $Project->services();
		my $Material = new openprint::Material( $$specs{'ddmPackageType'.$qty_index} );
    $package = $Material->name() if $Material->name();

    $$specs{'totalWeight'.$qty_index} = 0 if ! defined $$specs{'totalWeight'.$qty_index};

		if ( $$services{BulkSkids} ) {
			# The purpose of this is to put all the breakdown in the skids line and leave the other packaging summaries empty
			if ( $$services{BulkSkids}[0] == $service_id ) {
				if ($$specs{items_per_package}) {
					$summary .= 'around '.$$specs{items_per_package}.
						(($$specs{item_type} and ($$specs{item_type} eq 'FlatSheets')) ? ' flat sheets' : ' product').
						' per '.$package.'<br/>';
				}
				$summary .= $$specs{"txtPackageQuantity$qty_index"} . ' ' . $package . ( $$specs{"txtPackageQuantity$qty_index"} == 1 ? '' : 's' );
				my $g = $$specs{'totalWeight'.$qty_index} * 453.5923696;
				if ( $g > 1000 ) {
					$summary .= sprintf( ', Total Weight: %slbs (%skg)', 
							Number::Format::format_number( Math::Round::nearest( 1, $$specs{'totalWeight'.$qty_index}) ), 
							Number::Format::format_number( Math::Round::nearest( 1, $g/1000 ) ),
							);
				} else {
					$summary .= sprintf( ', Total Weight: %slbs (%sg)', 
							Number::Format::format_number( Math::Round::nearest( 1, $$specs{'totalWeight'.$qty_index}) ), 
							Number::Format::format_number( Math::Round::nearest( 1, $g ) ),
					);
				} # end if
			} else {
				if ( $$Material{name} ) {
					$summary .= $$specs{"txtPackageQuantity$qty_index"} . ' ' . $$Material{name} . 
						( $$specs{"txtPackageQuantity$qty_index"} == 1 ? '' : 's' );
				} # end if
			} # end if
		} else {
			if ( $$specs{ServiceType} eq 'Gaylords' ) {
				$summary .= $$specs{"txtPackageQuantity$qty_index"} . ( $$specs{"txtPackageQuantity$qty_index"} == 1 ? ' gaylord' : ' gaylords' );
				my $g = $$specs{'totalWeight'.$qty_index} * 453.5923696;
				if ( $g > 1000 ) {
					$summary .= sprintf( ', Total Weight: %slbs (%skg)', 
							Number::Format::format_number( Math::Round::nearest( 1, $$specs{'totalWeight'.$qty_index}) ), 
							Number::Format::format_number( Math::Round::nearest( 1, $g/1000 ) ),
							);
				} else {
					$summary .= sprintf( ', Total Weight: %slbs (%sg)', 
							Number::Format::format_number( Math::Round::nearest( 1, $$specs{'totalWeight'.$qty_index}) ), 
							Number::Format::format_number( Math::Round::nearest( 1, $g ) ),
					);
				} # end if
			} elsif ($$specs{"txtPackageQuantity$qty_index"}) {
				$summary .= $$specs{"txtPackageQuantity$qty_index"} . ' ' . $Material->name() . ( $$specs{"txtPackageQuantity$qty_index"} == 1 ? '' : 's' );
				my $g = $$specs{'totalWeight'.$qty_index} * 453.5923696;
				if ( $g > 1000 ) {
					$summary .= sprintf( ', Total Weight: %slbs (%skg)', 
							Number::Format::format_number( Math::Round::nearest( 1, $$specs{'totalWeight'.$qty_index}) ), 
							Number::Format::format_number( Math::Round::nearest( 1, $g/1000 ) ),
					);
				} else {
					$summary .= sprintf( ', Total Weight: %slbs (%sg)', 
							Number::Format::format_number( Math::Round::nearest( 1, $$specs{'totalWeight'.$qty_index}) ), 
							Number::Format::format_number( Math::Round::nearest( 1, $g ) ),
					);
				} # end if
			} # end if
		} # end if
	} else {
		if ( $$specs{items_per_package} ) {
			$summary .= 'maximum '.$$specs{items_per_package} . ' per '.$package.'<br/>';
		}
	} # end if
	return $summary;
} # end sub summary

sub overview_summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	$specs = openprint::service::get_specs_ref($Project, $service_id) if !$specs;
	my $package = 'skid';
	if ( $$specs{ServiceType} eq 'Gaylords' ) {
		$package = 'gaylord';
	}
	my $summary;

	my $services = $Project->services();
	my $Material = new openprint::Material($$specs{'ddmPackageType'.$qty_index});

	if ( $$services{BulkSkids} ) {
		# The purpose of this is to put all the breakdown in the skids line and leave the other packaging summaries empty
		if ( $$services{BulkSkids}[0] == $service_id ) {
			if ( $$specs{items_per_package} ) {
				$summary .= $$specs{"txtItemsPerPackage$qty_index"} . ' per '.$package.'<br/>';
			}
			$summary .= $$specs{"txtPackageQuantity$qty_index"} . ' ' . $package . ( $$specs{"txtPackageQuantity$qty_index"} == 1 ? '' : 's' );
if ( 0 ) {
			my $g = $$specs{'totalWeight'.$qty_index} * 453.5923696;
			if ( $g > 1000 ) {
				$summary .= sprintf( ', Total Weight: %slbs (%skg)', 
						Number::Format::format_number( Math::Round::nearest( 1, $$specs{'totalWeight'.$qty_index}) ), 
						Number::Format::format_number( Math::Round::nearest( 1, $g/1000 ) ),
						);
			} else {
				$summary .= sprintf( ', Total Weight: %slbs (%sg)', 
						Number::Format::format_number( Math::Round::nearest( 1, $$specs{'totalWeight'.$qty_index}) ), 
						Number::Format::format_number( Math::Round::nearest( 1, $g ) ),
				);
			} # end if
}
		} else {
			if ( $$Material{name} ) {
				$summary .= $$specs{"txtPackageQuantity$qty_index"} . ' ' . $$Material{name} . 
					( $$specs{"txtPackageQuantity$qty_index"} == 1 ? '' : 's' );
			} # end if
		} # end if
	} else {
		if ( $$specs{ServiceType} eq 'Gaylords' ) {
			$summary .= $$specs{"txtPackageQuantity$qty_index"} . ( $$specs{"txtPackageQuantity$qty_index"} == 1 ? ' gaylord' : ' gaylords' );
if ( 0 ) {
			my $g = $$specs{'totalWeight'.$qty_index} * 453.5923696;
			if ( $g > 1000 ) {
				$summary .= sprintf( ', Total Weight: %slbs (%skg)', 
						Number::Format::format_number( Math::Round::nearest( 1, $$specs{'totalWeight'.$qty_index}) ), 
						Number::Format::format_number( Math::Round::nearest( 1, $g/1000 ) ),
						);
			} else {
				$summary .= sprintf( ', Total Weight: %slbs (%sg)', 
						Number::Format::format_number( Math::Round::nearest( 1, $$specs{'totalWeight'.$qty_index}) ), 
						Number::Format::format_number( Math::Round::nearest( 1, $g ) ),
				);
			} # end if
}
		} else {
			$summary .= $$specs{"txtPackageQuantity$qty_index"} . ' ' . $Material->name() . ( $$specs{"txtPackageQuantity$qty_index"} == 1 ? '' : 's' );
if ( 0 ) {
			my $g = $$specs{'totalWeight'.$qty_index} * 453.5923696;
			if ( $g > 1000 ) {
				$summary .= sprintf( ', Total Weight: %slbs (%skg)', 
						Number::Format::format_number( Math::Round::nearest( 1, $$specs{'totalWeight'.$qty_index}) ), 
						Number::Format::format_number( Math::Round::nearest( 1, $g/1000 ) ),
				);
			} else {
				$summary .= sprintf( ', Total Weight: %slbs (%sg)', 
						Number::Format::format_number( Math::Round::nearest( 1, $$specs{'totalWeight'.$qty_index}) ), 
						Number::Format::format_number( Math::Round::nearest( 1, $g ) ),
				);
			} # end if
			} # end if
		} # end if
	} # end if
	return $summary;
} # end sub summary

sub save {
}

1;
__END__
