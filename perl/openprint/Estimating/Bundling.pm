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

package openprint::Estimating::Bundling;
use POSIX qw(ceil);
use vars qw( %ServicePrices %MaterialPrices );
%ServicePrices = (
		'BundlingMakeReady'	=> { },
		'BundlingMinimum'	=> { },
		'Bundling'			=> { units => [ 'per m', 'per bundle', 'per package' ] },
		);

require openprint::service;
require sql;

my @variables = (
	'txtItemsPerPackage','AccurateCount','bands_per_package','cross_bands_per_package',
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'Markup1','Markup2','Markup3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'MPrice1', 'MPrice2', 'MPrice3',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'txtPackageQuantity1', 'txtPackageQuantity2', 'txtPackageQuantity3',
	'rdbCardboardBacking',
	'type_id', 'cross_type_id',
  'alert',
);
sub variables {
  return @variables;
}

my @no_outputs = (
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'Markup1','Markup2','Markup3',
	'txtQuantity1','txtQuantity2','txtQuantity3',
	'txtItemsPerPackage','AccurateCount',
	'rdbCardboardBacking',
);

sub no_outputs {
	return @no_outputs;
}

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
  $$specs{alert} = '';
	if ( ! $$services{''} ) {
		$$specs{alert} .= 'Unable to find project service.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if
	my $ServiceType = $Project->ServiceType( $service_index );
	my $status = 'calculated';
	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
	if ( ! ( $$printing_specs{txtFinalWidth} and $$printing_specs{txtFinalHeight} ) ) {
		my @sigs = $Project->signatures();
		if ( ! @sigs ) {
			$$specs{alert} .= 'There are no signatures... cannot determine size.<br/>';
			return $$specs{Status} = 'uncalculated';
		} # end if
		foreach my $sig_id ( @sigs ) {
			$printing_specs = openprint::service::get_specs_ref( $Project, $sigs[0] );
			last if $$printing_specs{txtFinalWidth} and $$printing_specs{txtFinalHeight};
		} # end foreach
	} # end if
	if ( ! ( $$printing_specs{txtFinalWidth} and $$printing_specs{txtFinalHeight} ) ) {
		$openprint::log->error('Unable to determine dimensions.<br/>');
		$$specs{alert} .= 'Unable to determine dimensions.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	$$specs{txtItemsPerPackage} = defined $$specs{txtItemsPerPackage} ? int($$specs{txtItemsPerPackage}) : 0;
	if ( !$$specs{txtItemsPerPackage} ) {
# a zero value is still calculated, just with a zero price.
		if ( $ServiceType->name() eq 'Bundling' ) {
			$$specs{alert} .= 'Please enter the # of items in each bundle';
		} elsif ( $ServiceType->name() eq 'ShrinkWrap' ) {
			$$specs{alert} .= 'Please enter the # of items in each wrap';
		} else {
			$$specs{alert} .= 'Please enter the # of items in each ' . $ServiceType->name();
		} # end if
    return $$specs{Status} = 'uncalculated';
	} # end if
	if ( ! $$specs{rdbCardboardBacking} ) {
		$$specs{alert} = 'Please select whether you need cardboard backing.';
		return $$specs{Status} = 'uncalculated';
	} # end if

	$$specs{bands_per_package} =~ s/[^\d\.]//g if $$specs{bands_per_package};
	$$specs{cross_bands_per_package} =~ s/[^\d\.]//g if $$specs{cross_bands_per_package};
	my $makeReady = openprint::service::get_price( $ServiceType->name().'MakeReady', undef, undef ) || 0;
	my $Service = openprint::Service->find_one( name=>$ServiceType->name() );
	my $minCharge = openprint::service::get_price( $ServiceType->name().'Minimum', undef, undef );
	if ( ! $minCharge ) {
		$log->error('No minimum charge lets do debug '.$$specs{ServiceType}.' '.$ServiceType->to_string());
		my $Minimum = openprint::Service->find_one( name=>$ServiceType->name().'Minimum' );
		if ( $Minimum ) {
			$log->error('Service: ' . $Minimum->to_string());
		} else {
			$log->error('No ServiceMinimum');
		} # end if
	}
	my @Materials;
	my @CrossMaterials;
	foreach my $M ( openprint::Material->find( category=>$ServiceType->name, order=>'lower(name)' ) ) {
		if ( $M->name() =~ /cross/i ) {
			push @CrossMaterials, $M;
		} else {
			push @Materials, $M;
		}
	} # end foreach Material
	
	if ( scalar @Materials == 1 ) {
		$$specs{type_id} = $Materials[0]->id();
	} elsif ( @Materials and $$specs{bands_per_package} ) {
		if ( ! $$specs{type_id} ) {
			$$specs{alert} .= 'Please select the type of band.<br/>';
			$status = 'uncalculated';
		}
	} # end if
	if ( scalar @CrossMaterials == 1 ) {
		$$specs{cross_type_id} = $CrossMaterials[0]->id();
	} elsif ( @CrossMaterials and $$specs{cross_bands_per_package} ) {
		if ( ! $$specs{cross_type_id} ) {
			$$specs{alert} .= 'Please select the type of cross bands.<br/>';
			$status = 'uncalculated';
		}
	} # end if

	my $Material = openprint::Material->find_one( id=>$$specs{type_id} );
	my $CrossMaterial = openprint::Material->find_one( id=>$$specs{cross_type_id} );
	if ( $$specs{cross_bands_per_package} and ! $$specs{bands_per_package} ) {
		@CrossMaterials = @Materials;
		$CrossMaterial = $Material;
	}
  my $MaterialService = openprint::Service->find_one(name=>$Material->name()) if $Material;
  my $MaterialMRService = openprint::Service->find_one(name=>$Material->name().'MakeReady') if $Material;
	
	if ( ! ( $$specs{cross_bands_per_package} or $$specs{bands_per_package} ) ) {
		$$specs{alert} .= 'Please enter the # bands.<br/>';
		return $status = 'uncalculated';
	} # end if

	my $Cardboard = openprint::Material->find_one( name=>'CardboardBacking' );

	foreach my $qty_index ( $Project->quantity_indexes() ) {

		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"Markup$qty_index"};
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtPrice$qty_index"};
		$$specs{"txtQuantity$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtQuantity$qty_index"};
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		my $qty = $$specs{txtPressSheetComboItems} ? $$specs{'txtQuantity'.$qty_index} * $$specs{txtPressSheetComboItems} : $$specs{'txtQuantity'.$qty_index};
		next if ! $qty;

		if ( $$services{Signature} and @{$$services{Signature}} ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $$services{Signature}[0] );
			if ( $$sig_specs{Versions} ) {
				my $versions_per_package = int( $qty / $$sig_specs{Versions} );
        $openprint::log->debug("Per package due to versions: $qty / $$sig_specs{Versions} = $versions_per_package");
				if ( $versions_per_package < $$specs{txtItemsPerPackage} ) {
					$$specs{txtItemsPerPackage} = $versions_per_package;
				} # end if
			} else {
				# No versions?
        #$openprint::log->debug('No versions');
			} # end if
		} else {
			$openprint::log->debug('No signatnures');
		} # end if
		my $package_qty = $$specs{txtItemsPerPackage} ? ceil( $qty/$$specs{txtItemsPerPackage} ) : 0;
		my $m_qty = $$specs{txtItemsPerPackage} ? ceil( 1000/$$specs{txtItemsPerPackage} ) : 0;

		$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Minimum Charge: $%.2f<br/>', $minCharge );
		$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Makeready: $%.2f<br/>', $makeReady);
		my $price = 0;
		my $mprice = 0;
		my $unitPrice = 0;
		my %ServicePrice = $Service->get_price( $qty, undef ) if $Service;
		if ( %ServicePrice ) {
			if ( $ServicePrice{units} eq 'per m' ) {
				$ServicePrice{MPrice} = $ServicePrice{Price};
				$ServicePrice{Total} = $ServicePrice{Price} * $qty / 1000;
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('ServicePrice %1$.2f%2$s * %4$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $qty );
			} elsif ( $ServicePrice{units} eq 'each' ) {
				$ServicePrice{MPrice} = $ServicePrice{Price} * 1000;
				$ServicePrice{Total} = $ServicePrice{Price} * $qty;
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('ServicePrice %1$.2f%2$s * %4$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $qty );
			} elsif ( sets::isin( $ServicePrice{units}, [ 'per bundle', 'per package' ] ) ) {
				$ServicePrice{Total} = $ServicePrice{Price} * $package_qty;
				$ServicePrice{MPrice} = $ServicePrice{Price} * $m_qty;
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('ServicePrice %1$.2f%2$s * %4$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $package_qty );
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('No units set for %s (%s)<br/>', $ServiceType->name(), $ServicePrice{units} );
			} # end if
			$unitPrice += $ServicePrice{Total};
			$mprice += $ServicePrice{MPrice};
		} # end if

    if ($MaterialService) {
      my %MaterialServicePrice = $MaterialService->get_price( $qty, undef );
      if ( %MaterialServicePrice ) {
        if ( $MaterialServicePrice{units} eq 'per m' ) {
          $MaterialServicePrice{MPrice} = $MaterialServicePrice{Price};
          $MaterialServicePrice{Total} = $MaterialServicePrice{Price} * $qty / 1000;
          $$specs{'hdnBreakdown'.$qty_index} .= $Material->description().sprintf(' $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @MaterialServicePrice{'Price','units','Total'}, $qty );
        } elsif ( $MaterialServicePrice{units} eq 'each' ) {
          $MaterialServicePrice{MPrice} = $MaterialServicePrice{Price} * 1000;
          $MaterialServicePrice{Total} = $MaterialServicePrice{Price} * $qty;
          $$specs{'hdnBreakdown'.$qty_index} .= $Material->description().sprintf(' $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @MaterialServicePrice{'Price','units','Total'}, $qty );
        } elsif ( $MaterialServicePrice{units} eq 'per bundle' or $MaterialServicePrice{units} eq 'per package') {
          $MaterialServicePrice{Total} = $MaterialServicePrice{Price} * $package_qty;
          $MaterialServicePrice{MPrice} = $MaterialServicePrice{Price} * $m_qty;
          $$specs{'hdnBreakdown'.$qty_index} .= $Material->description().sprintf(' $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @MaterialServicePrice{'Price','units','Total'}, $package_qty );
        } else {
          $$specs{'hdnBreakdown'.$qty_index} .= sprintf('No units set ffor service %s (%s)<br/>', $Material->description(), $MaterialServicePrice{units} );
          $MaterialServicePrice{Total} = $MaterialServicePrice{Price} * $package_qty;
        } # end if
        $unitPrice += $MaterialServicePrice{Total};
        $mprice += $MaterialServicePrice{MPrice};
      } # end if
    }
		$price = $unitPrice + $makeReady;

    if ($MaterialMRService) {
      my %MaterialMRServicePrice = $MaterialMRService->get_price( $qty, undef );
      if ( %MaterialMRServicePrice ) {
        $MaterialMRServicePrice{Total} = $MaterialMRServicePrice{Price};
        $$specs{'hdnBreakdown'.$qty_index} .= $MaterialMRService->description().sprintf(' $%.2f<br/>', $MaterialMRServicePrice{Total});
        $price += $MaterialMRServicePrice{Total};
      } # end if
    }

		if ( $$specs{rdbCardboardBacking} eq 'Y' ) {
			if ( $Cardboard ) {
				my %CardboardPrice = $Cardboard->get_price( $package_qty, undef );
				if ( $CardboardPrice{units} eq 'per square inch' ) {
					$CardboardPrice{PackagePrice} = $CardboardPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight};
					$CardboardPrice{Total} = $CardboardPrice{PackagePrice} * $package_qty;
					$CardboardPrice{MPrice} = $CardboardPrice{PackagePrice} * $m_qty;

					$$specs{'hdnBreakdown'.$qty_index} .= sprintf(
							'Cardboard Price: $%.2f %s * %s x %s = $%.2f per package = %.2f total<br/>',
							@CardboardPrice{'Price','units'}, @$printing_specs{'txtFinalWidth','txtFinalHeight'}, @CardboardPrice{'PackagePrice','Total'} );
				} elsif ( $CardboardPrice{units} eq 'per square foot' ) {
					$CardboardPrice{PackagePrice} = $CardboardPrice{Price} * ($$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight}/144);
					$CardboardPrice{Total} = $CardboardPrice{PackagePrice} * $package_qty;
					$CardboardPrice{MPrice} = $CardboardPrice{PackagePrice} * $m_qty;
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Cardboard Price: $%.2f %s * %s x %s = $%.2f per package = %.2f total<br/>',
							@CardboardPrice{'Price','units'}, @$printing_specs{'txtFinalWidth','txtFinalHeight'}, @CardboardPrice{'PackagePrice','Total'} );
				} elsif ( $CardboardPrice{units} eq 'per pad' or $CardboardPrice{units} eq 'each' ) {
					$CardboardPrice{Total} = $CardboardPrice{Price} * $package_qty;
					$CardboardPrice{MPrice} = $CardboardPrice{Price} * $m_qty;
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Cardboard Price: $%.2f %s x %d packages = %.2f<br/>',
							@CardboardPrice{'Price','units'}, $package_qty, $CardboardPrice{Total} );
				} else {
					$$specs{alert} .= "Unknown units specified on cardboard backing.<br/>";
					$openprint::log->error("Unknown units specified on cardboard backing.($CardboardPrice{units})");
					$CardboardPrice{Total} = $CardboardPrice{Price};
				} # end if
				$price += $CardboardPrice{Total};
				$mprice += $CardboardPrice{MPrice};
			} # end if
		} # end if rdbCardboardBacking

		if ( @Materials ) {
			if ( $Material ) {

				my $material_qty = $package_qty * $$specs{bands_per_package};
				my $m_material_qty = $m_qty * $$specs{bands_per_package};
				my %MaterialPrice = $Material->get_price($material_qty);
# if $$specs{bands_per_package};
				if ( $MaterialPrice{units} eq 'per m' ) {
					%MaterialPrice = $Material->get_price($package_qty);
					$MaterialPrice{Total} = $MaterialPrice{Price} * $material_qty / 1000;
					$MaterialPrice{MPrice} = $MaterialPrice{Price} * $m_material_qty / 1000;
				} elsif ( $MaterialPrice{units} eq 'each' ) {
					$MaterialPrice{Total} = $MaterialPrice{Price} * $material_qty;
					$MaterialPrice{MPrice} = $MaterialPrice{Price} * $m_material_qty;
				} elsif ( $MaterialPrice{units} eq 'per inch' ) {
					%MaterialPrice = $Material->get_price( $package_qty );
					$MaterialPrice{Total} = $MaterialPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight} * $material_qty;
					$MaterialPrice{MPrice} = $MaterialPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight} * $m_material_qty;
				} elsif ( $MaterialPrice{units} eq 'per foot' ) {
					%MaterialPrice = $Material->get_price( $package_qty );
					$MaterialPrice{Total} = $MaterialPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight} * $material_qty / 144;
					$MaterialPrice{MPrice} = $MaterialPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight} * $m_material_qty / 144;
				} elsif ( $MaterialPrice{units} eq 'per bundle' ) {
					$MaterialPrice{Total} = $MaterialPrice{Price} * $package_qty;
					$MaterialPrice{MPrice} = $MaterialPrice{Price} * $m_qty;
				} else {
					$openprint::log->error("Uknown units on $$Material{name} $$Material{description}");
				} # end if
				$price += $MaterialPrice{Total};
				$unitPrice += $MaterialPrice{Total};
				$mprice += $MaterialPrice{MPrice};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material Price: $%1$.2f%2$s * %4$d packages * %5$d per package = $%3$.2f<br/>',@MaterialPrice{'Price','units','Total'}, $package_qty, $$specs{bands_per_package} );
			} # end if
			if ( $$specs{cross_bands_per_package} and $CrossMaterial ) {
				my %MaterialPrice = $CrossMaterial->get_price( $package_qty );

				my $material_qty = $package_qty * $$specs{cross_bands_per_package};
				my $m_material_qty = $m_qty * $$specs{cross_bands_per_package};
# if $$specs{bands_per_package};
				if ( $MaterialPrice{units} eq 'per m' ) {
					$MaterialPrice{Total} = $MaterialPrice{Price} * $material_qty / 1000;
					$MaterialPrice{MPrice} = $MaterialPrice{Price} * $m_material_qty / 1000;
				} elsif ( $MaterialPrice{units} eq 'each' ) {
					$MaterialPrice{Total} = $MaterialPrice{Price} * $material_qty;
					$MaterialPrice{MPrice} = $MaterialPrice{Price} * $m_material_qty;
				} elsif ( $MaterialPrice{units} eq 'per inch' ) {
					$MaterialPrice{Total} = $MaterialPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight} * $material_qty;
					$MaterialPrice{MPrice} = $MaterialPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight} * $m_material_qty;
				} elsif ( $MaterialPrice{units} eq 'per foot' ) {
					$MaterialPrice{Total} = $MaterialPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight} * $material_qty / 144;
					$MaterialPrice{MPrice} = $MaterialPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight} * $m_material_qty / 144;
				} elsif ( $MaterialPrice{units} eq 'per bundle' ) {
					$MaterialPrice{Total} = $MaterialPrice{Price} * $package_qty;
					$MaterialPrice{MPrice} = $MaterialPrice{Price} * $m_qty;
				} else {
					$openprint::log->error("Uknown units on $$CrossMaterial{name} $$CrossMaterial{description}");
				} # end if
				$price += $MaterialPrice{Total};
				$mprice += $MaterialPrice{MPrice};
				$unitPrice += $MaterialPrice{Total};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Cross Material Price: $%1$.2f%2$s * %4$d packages * %5$d per package = $%3$.2f<br/>',@MaterialPrice{'Price','units','Total'}, $package_qty, $$specs{cross_bands_per_package} );
			} # end if
		} # end if Materials
		$price = $minCharge if $price < $minCharge;

		$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Total: $%.2f<br/>',$price );
		$$specs{'txtPackageQuantity'.$qty_index} = $package_qty;
			if ( $$specs{"Markup$qty_index"} ) {
				$price *= (1+$$specs{"Markup$qty_index"}/100);
			}
			if ( $Project->markup() ) {
			 	$price *= (1+$Project->markup()/100);
			 	$mprice *= (1+$Project->markup()/100);
			 	$unitPrice *= (1+$Project->markup()/100);
		
			}
		if ( (!$$specs{'OverridePrice'.$qty_index}) or ($$specs{'OverridePrice'.$qty_index} ne 'Y') ) {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $price);
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
		} # endif
		$$specs{"txtUnitPrice$qty_index"} = sprintf($openprint::config{UnitPriceFormat}, $unitPrice/$qty);
		$$specs{"MPrice$qty_index"} = sprintf($openprint::config{UnitPriceFormat}, $mprice);
	} # end foreach

	return $$specs{Status} = $status;
} # end sub calc

sub summary {
	my ($Project, $service_id, $specs, $qty_index) = @_;

	$specs = openprint::service::get_specs_ref($Project, $service_id) if ! $specs;
	my $text = '';
	if ( $qty_index ) {
		$text .= $$specs{'txtPackageQuantity'.$qty_index};
		if ( $$specs{ServiceType} =~ /Wrap/i ) {
			$text .= ' wrap' . ($$specs{'txtPackageQuantity'.$qty_index} > 1 ? 's' : '');
		} elsif ( $$specs{ServiceType} =~ /Bundling/i ) {
			$text .= ' bundle' . ($$specs{'txtPackageQuantity'.$qty_index} > 1 ? 's' : '');
		} elsif ( $$specs{ServiceType} =~ /Banding/i ) {
			$text .= ' bundle' . ($$specs{'txtPackageQuantity'.$qty_index} > 1 ? 's' : '');
		} # end if
	} elsif ($$specs{txtItemsPerPackage}) {
		$text .= $$specs{txtItemsPerPackage} . ' items';
		if ( $$specs{ServiceType} =~ /Wrap/i ) {
			$text .= ' per wrap';
		} elsif ( $$specs{ServiceType} =~ /Bundling/i ) {
			$text .= ' per bundle';
		} elsif ( $$specs{ServiceType} =~ /Banding/i ) {
			$text .= ' per band';
			$text .= sprintf(' %d bands each', $$specs{bands_per_package} ) if $$specs{bands_per_package};
		} # end if
		if ( $$specs{type_id} ) {
			my $Material = new openprint::Material($$specs{type_id});
			$text .= ' ' . $Material->description() . ' ';
		} 
		if ( $$specs{cross_type_id} and $$specs{cross_bands_per_package}) {
			my $CrossMaterial = new openprint::Material($$specs{cross_type_id});
			$text .= ' ' . $CrossMaterial->description() . ' ';
		} 

		$text .= $$specs{rdbCardboardBacking} eq 'Y' ? ' with cardboard backing.' : '';
	} # end if
$openprint::log->debug("Bundling:: summary");
	return $text;
} # end sub summary

sub save {
	my ( $project_index, $service_index, $param ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

	if ( ($$param{AccurateCount} and ($$param{AccurateCount} eq 'Y') ) and ! $$services{Counting} ) {
		$Project->add_service('Counting');
	} # end if
} # end sub save

sub has_overrides {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

	my @v;
	if ( $qty_index ) {
		push @v, map { $$specs{$_.$qty_index} ? $_ : () } (
				'OverridePrice',
				);
	} # end if

	return @v;

} # end sub has_overrides
1;
__END__
