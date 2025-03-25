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

use constant DEBUG => 1;

use strict;
package openprint::Estimating::ShrinkWrapping;
use vars qw( %ServicePrices );

use POSIX qw(ceil);
use warnings;

require openprint::service;
require openprint::Project;

%ServicePrices = (
    ShrinkWrap => { units => [ 'per m', 'each','per bundle', 'per package', 'per hour' ] },
	ShrinkWrapMakeReady	=> { units => [ ] },
);

my @variables = (
	'txtItemsPerPackage','AccurateCount','bands_per_package',
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
	'Markup1','Markup2','Markup3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'txtPackageQuantity1', 'txtPackageQuantity2', 'txtPackageQuantity3',
	'rdbCardboardBacking',
	'type_id',
	'material_id',
	'ddmEquipment1','ddmEquipment2', 'ddmEquipment3',
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
	$$specs{alert} = '';

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
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

	$$specs{txtItemsPerPackage} = int($$specs{txtItemsPerPackage}) if $$specs{txtItemsPerPackage};
	if ( ! $$specs{txtItemsPerPackage} ) {	# a zero value is still calculated, just with a zero price.d
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

	my $calliper = $Project->calliper();
	

	$$specs{bands_per_package} =~ s/[^\d\.]//g if $$specs{bands_per_package};

	my @Equipment = openprint::Equipment->find( useinestimating=>1, 'servicetype_id any'=>$ServiceType->id() );
	my $Service = openprint::Service->find_one( name=> $ServiceType->name() );
	my $MakeReady = openprint::Service->find_one( name=> $ServiceType->name().'MakeReady' );
	my $Minimum = openprint::Service->find_one( name=> $ServiceType->name().'Minimum' );
	my $Cardboard = openprint::Material->find_one( name=>'CardboardBacking');
	my @Materials = openprint::Material->find( category=>$ServiceType->name() );

	my $length = ( $$printing_specs{txtFinalWidth} > $$printing_specs{txtFinalHeight} ? $$printing_specs{txtFinalHeight} : $$printing_specs{txtFinalWidth} );
	my $bundle_height = $$specs{txtItemsPerPackage} * $calliper;
	my $inches = $length + ( $bundle_height * 2 );

	foreach my $qty_index ( $Project->quantity_indexes() ) {

		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"Markup$qty_index"};
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtPrice$qty_index"};
		$$specs{"txtQuantity$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtQuantity$qty_index"};
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		my $qty = $$specs{txtPressSheetComboItems} ? $$specs{'txtQuantity'.$qty_index} * $$specs{txtPressSheetComboItems} : $$specs{'txtQuantity'.$qty_index};
		next if ! $qty;

		my $package_qty = $$specs{txtItemsPerPackage} ? ceil( $qty/$$specs{txtItemsPerPackage}) : 0;

		my %bestPrice;

		foreach my $Equipment ( @Equipment ? @Equipment : ( undef ) ) {
			my %makeReady = $MakeReady->get_price( undef, $Equipment ) if $MakeReady;
			my %minCharge = $Minimum->get_price( undef, $Equipment ) if $Minimum;

			my $total_inches = $package_qty * $inches;

			$$specs{'hdnBreakdown'.$qty_index} .= 'Item height: ' . $calliper . ' Bundle height: ' . $bundle_height . 'inches<br/>';
			$$specs{'hdnBreakdown'.$qty_index} .= 'Dimension used for amount of film calculation: ' . $length . ' total length of film used per bundle: ' . $inches. 'inches, total: ' . $total_inches . '<br/>';

			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Minimum Charge: $%.2f<br/>', $minCharge{Price} );
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Makeready: $%.2f<br/>', $makeReady{Price} );
			my $price = 0;
			my $unitPrice = 0;
			my %ServicePrice = $Service->get_price( $qty, $Equipment );
			if ( %ServicePrice ) {
				if ( $ServicePrice{units} eq 'per m' ) {
					$ServicePrice{Total} = $ServicePrice{Price} * $qty / 1000;
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('ServicePrice %1$.2f%2$s * %4$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $qty );
				} elsif ( $ServicePrice{units} eq 'each' ) {
					$ServicePrice{Total} = $ServicePrice{Price} * $qty;
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('ServicePrice %1$.2f%2$s * %4$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $qty );
				} elsif ( sets::isin( $ServicePrice{units}, [ 'per bundle', 'per package' ] ) ) {
					$ServicePrice{Total} = $ServicePrice{Price} * $package_qty;
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('ServicePrice %1$.2f%2$s * %4$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $package_qty );
				} elsif ( $ServicePrice{units} eq 'per hour' ) {
					my $Runspeed = $Equipment->Specification('Runspeed');
					if ( ! $Runspeed ) {
						$$specs{'hdnBreakdown'.$qty_index} .= 'No runspeed specified.<br/>';
						next;
					} # end if
					my $hours = Math::Round::nearest(0.01, $total_inches / $Runspeed->value() ) if $Runspeed->value();
					$ServicePrice{Total} = $ServicePrice{Price} * $hours;
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('%3$s inches * %4$d = %5$sinches, @ %1$d%2$s = %6$shours<br/>', @$Runspeed{'value','units'}, $length, $package_qty, $total_inches, $hours );
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('ServicePrice $%1$.2f%2$s * %4$.2f hours = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $hours );
				} else {
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('No units set for %s (%s)<br/>', $ServiceType->name(), $ServicePrice{units} );
				} # end if
				$unitPrice += $ServicePrice{Total};
			} # end if
			$price = $unitPrice + $makeReady{Price};

			if ( $$specs{rdbCardboardBacking} eq 'Y' ) {
				if ( $Cardboard ) {
					my %CardboardPrice = $Cardboard->get_price( $package_qty, undef );
					if ( $CardboardPrice{units} eq 'per square inch' ) {
						$CardboardPrice{Total} = $CardboardPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight};
					} elsif ( $CardboardPrice{units} eq 'per square foot' ) {
						$CardboardPrice{Total} = $CardboardPrice{Price} * ($$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight}/144);
					} elsif ( $CardboardPrice{units} eq 'per pad' ) {
						$CardboardPrice{Total} = $CardboardPrice{Price};
					} elsif ( $CardboardPrice{units} eq 'each' ) {
						$CardboardPrice{Total} = $CardboardPrice{Price};
					} else {
$openprint::log->error("Unknown units set on cardboard price!");
					} # end if

$openprint::log->debug("Cardboard size: $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight}");
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Cardboard Price: $%.2f %s * %s x %s = $%.2f per package = $%.2f<br/>',@CardboardPrice{'Price','units'}, @$printing_specs{'txtFinalWidth','txtFinalHeight'}, $CardboardPrice{Total}, $CardboardPrice{Total}*$package_qty );
					$price += $CardboardPrice{Total} * $package_qty;
				} # end if
			} # end if rdbCardboardBacking 

			if ( @Materials ) {
				if ( scalar @Materials == 1 ) {
					$$specs{type_id} = $Materials[0]->id();
				} # end if
				if ( ! $$specs{type_id} ) {
					$$specs{alert} .= 'Please select the type of ' . $ServiceType->name() . '<br/>';
					$status = 'uncalculated';
				} else {
					my $Material = new openprint::Material( $$specs{type_id} );
					my %MaterialPrice = $Material->get_price( $package_qty );

					my $material_qty = $package_qty;
					$material_qty *= $$specs{bands_per_package} if $$specs{bands_per_package};
					if ( %MaterialPrice ) {
# if $$specs{bands_per_package};
						if ( $MaterialPrice{units} eq 'per m' ) {
							$MaterialPrice{Total} = $MaterialPrice{Price} * $material_qty / 1000;
							$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material Price: $%1$.2f%2$s * %4$d packages * %5$d per package = $%3$.2f<br/>',@MaterialPrice{'Price','units','Total'}, $package_qty, $$specs{bands_per_package} );
						} elsif ( $MaterialPrice{units} eq 'each' ) {
							$MaterialPrice{Total} = $MaterialPrice{Price} * $material_qty;
							$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material Price: $%1$.2f%2$s * %4$d packages * %5$d per package = $%3$.2f<br/>',@MaterialPrice{'Price','units','Total'}, $package_qty, $$specs{bands_per_package} );
						} elsif ( $MaterialPrice{units} eq 'per inch' ) {
							$MaterialPrice{Total} = $MaterialPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight} * $material_qty;
							$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material Price: $%1$.2f%2$s * %4$d packages * %5$d per package = $%3$.2f<br/>',@MaterialPrice{'Price','units','Total'}, $package_qty, $$specs{bands_per_package} );
						} elsif ( $MaterialPrice{units} eq 'per foot' ) {
							my $Roll_Length = $Material->Specification('Length');
							if ( $Roll_Length ) {
								$MaterialPrice{Total} = Math::Round::nearest( 0.01, $MaterialPrice{Price} * $total_inches / 12 );
								$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material Price: $%1$.4f%2$s * %4$d feet = $%3$.2f<br/>',@MaterialPrice{'Price','units','Total'}, $total_inches/12, $$specs{bands_per_package} );
							} else {
								$MaterialPrice{Total} = $MaterialPrice{Price} * $$printing_specs{txtFinalWidth} * $$printing_specs{txtFinalHeight} * $material_qty / 144;
								$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material Price: $%1$.2f%2$s * %4$d packages * %5$d per package = $%3$.2f<br/>',@MaterialPrice{'Price','units','Total'}, $package_qty, $$specs{bands_per_package} );
							} # ebnd if
						} elsif ( $MaterialPrice{units} eq 'per roll' ) {
							my $Roll_Length = $Material->Specification('Length');
							if ( ! $Roll_Length ) {
								$$specs{'hdnBreakdown'.$qty_index} .= 'Unable to find roll Length.  Assuming  42000Inches.<br/>';
								$Roll_Length = { value => 42000, units=>'inches' };
							} # end if

							$$specs{'hdnBreakdown'.$qty_index} .= 'Length per roll : ' . $$Roll_Length{value}.$$Roll_Length{units} . '<br/>';

							my $rolls = ceil( $total_inches / $$Roll_Length{value} );
							$MaterialPrice{Total} = $MaterialPrice{Price} * $rolls;
							$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material Price: $%1$.2f%2$s * %4$d rolls = $%3$.2f<br/>',@MaterialPrice{'Price','units','Total'}, $rolls );
						} # end if
						$price += $MaterialPrice{Total};
						$unitPrice += $MaterialPrice{Total};
					} # end if %MaterialPrice
				} # end if
			} # end if Materials
			$price = $minCharge{Price} if $price < $minCharge{Price};
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Total: $%.2f<br/>',$price );

			if ( ( ! %bestPrice ) or ( $price < $bestPrice{Total} ) ) {
				$bestPrice{Total} = $price;
				$bestPrice{Equipment} = $Equipment;
				$bestPrice{Unit} = $unitPrice;
			} # end if
		} # end foreach Equipment

		$$specs{'txtPackageQuantity'.$qty_index} = $package_qty;

		$bestPrice{Unit} = $bestPrice{Unit}/$qty;
		if ( $Project->markup() ) {
			$bestPrice{Unit} *= (1+$Project->markup()/100);
			$bestPrice{Total} *= (1+$Project->markup()/100);
		}
			
		$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, 
			$openprint::config{UnitPriceRounding} ? Math::Round::nearest( $openprint::config{UnitPriceRounding}, $bestPrice{Unit} ) : $bestPrice{Unit} );

		if ( ( ! exists $$specs{'OverridePrice'.$qty_index} ) or ( $$specs{'OverridePrice'.$qty_index} ne 'Y' ) ) {

			if ( $$specs{"Markup$qty_index"} ) {
				$bestPrice{Total} *= ( 1+$$specs{"Markup$qty_index"}/100 );
			}
			
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, 
					( $openprint::config{ProjectPriceRounding} ? Math::Round::nearest( $openprint::config{ProjectPriceRounding}, $bestPrice{Total} ) : $bestPrice{Total} )
					);
		} else {
			$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
		} # endif
		$$specs{"ddmEquipment$qty_index"} = $bestPrice{Equipment} ? $bestPrice{Equipment}->id() : '';
	} # end foreach qty_index

	return $$specs{Status} = $status;
} # end sub calc

sub summary {
  my ( $Project, $service_id, $specs, $qty_index ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
  my $text = '';
  if ( $qty_index ) {
    if ($$specs{'txtPackageQuantity'.$qty_index}) {
      $text .= $$specs{'txtPackageQuantity'.$qty_index};
      if ( $$specs{ServiceType} =~ /Wrap/i ) {
        $text .= ' wrap' . ($$specs{'txtPackageQuantity'.$qty_index} > 1 ? 's' : '');
      } elsif ( $$specs{ServiceType} =~ /Bundling/i ) {
        $text .= ' bundle' . ($$specs{'txtPackageQuantity'.$qty_index} > 1 ? 's' : '');
      } elsif ( $$specs{ServiceType} =~ /Banding/i ) {
        $text .= ' bundle' . ($$specs{'txtPackageQuantity'.$qty_index} > 1 ? 's' : '');
      } # end if
    } # end if
  } elsif ( $$specs{txtItemsPerPackage} and int($$specs{txtItemsPerPackage}) ) {
    $text .= $$specs{txtItemsPerPackage} . ' items';
    if ( $$specs{ServiceType} =~ /Wrap/i ) {
      $text .= ' per wrap';
    } elsif ( $$specs{ServiceType} =~ /Bundling/i ) {
      $text .= ' per bundle';
    } elsif ( $$specs{ServiceType} =~ /Banding/i ) {
      $text .= ' per band';
      $text .= sprintf(' %d bands each', $$specs{bands_per_package} ) if $$specs{bands_per_package};
    } # end if
    $text .= $$specs{rdbCardboardBacking} eq 'Y' ? ' with cardboard backing.' : '';
  } # end if
  return $text;
} # end sub summary

sub display {
	my ( $variable, $Project, $service_index ) = @_;
	my $ServiceType = $Project->ServiceType( $service_index );
	$$variable{Equipment} = [ openprint::Equipment->find( 'servicetype_id any'=>$ServiceType->id(), useinestimating=>1, order=>'lower(strName)') ];
} # end sub display

sub save {
	my ( $project_index, $service_index, $param ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();

	if ( (defined $$param{AccurateCount} ) and ( $$param{AccurateCount} eq 'Y' ) and ! $$services{Counting} ) {
		$Project->add_service( 'Counting' );
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
