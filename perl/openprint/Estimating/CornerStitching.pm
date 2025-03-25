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

package openprint::Estimating::CornerStitching;
use strict;
use warnings;

require openprint::Equipment;
require openprint::service;

require sql;

my @possible_pages = ( 2, 4, 6, 8, 12, 16, 20, 24, 32, 36, 40, 48, 64 );

# This is an array of all the variables that need to be saved to the database for this service.
my @variables = (
		'alert',
		'txtPageQuantity',
    'txtCalliper',
		'ddmEquipment1',
		'ddmEquipment2',
		'ddmEquipment3',
		'txtPrice1',
		'txtPrice2',
		'txtPrice3',
		'txtQuantity1',
		'txtQuantity3',
		'txtQuantity2',
		'ServiceType',
		'txtRunTime1',
		'txtRunTime2',
		'txtRunTime3',
    map { (
      'txtSignatureQty'.$_.'Page-1'=>['save','output'],
      'txtSignatureQty'.$_.'Page-2'=>['save','output'],
      'txtSignatureQty'.$_.'Page-3'=>['save','output'],
      ) } @possible_pages,
		);

sub variables {
    return @variables;
}

my @possible_pages = ( 2, 4, 6, 8, 12, 16, 20, 24, 32, 36, 40, 48, 64 );

# A function that is smart enough to return true if the project needs folding, and false if it doesn't.
sub neccessary {
	my ( $log, $dbh, $project_index ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
	if ( $$services{NoBindery} ) {
		$log->debug(" ** Project is marked as No bindery, Folding not needed ! ** ");
		return 0;
	} # end if

	if ( $$services{''} ) {
		my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
		if ( $$printing_specs{rdbTemplateType} eq 'CornerStitching' ) {
			return 1;
		} # end if
	} # end if

	return 0;
} # end sub neccessary


# Corner Stiching is simple:  Max 96 pages, setup plus per 1000 charge
#

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

  $$specs{alert} = '';
	my $status = 'calculated';

	my $Project = new openprint::Project( $project_index );
  my $ServiceType = $Project->ServiceType($service_index);
	my %services = $Project->get_services();

	if (!$services{''}) {
		$$specs{alert} = 'No Project service found.<br/>';
		return 'uncalculated';
	} # end if

	my $printing_service_index = $services{''}[0];
  my $printing_specs = openprint::service::get_specs_ref( $Project, $printing_service_index );
	if ( $$printing_specs{txtTotalPageQuantity} <= 0 ) {
		$$specs{alert} .= 'Unknown # of pages<br/>';
		$status = 'uncalculated';
	} # end if
	@$specs{'txtPageQuantity','txtFinalWidth','txtFinalHeight'} = @$printing_specs{'txtTotalPageQuantity','txtFinalWidth','txtFinalHeight'};
  $$specs{txtCalliper} = $Project->calliper();

  my @signatures = $Project->signatures();
  if ( ! @signatures ) {
    $$specs{alert} .= 'Unable to find any signatures to stitch.<br/>';
    return $$specs{Status} = 'uncalculated';
  } # end if

  my $error = '';
  my @all_equipment = openprint::Equipment->find(
    'servicetype_id any' => $ServiceType->id(),
    useinestimating=>1, order=>'strName');
  if ( ! @all_equipment ) {
    # alert the user that no equipment is good.
    $$specs{alert} = "We have no equipment for Corner Stitching.<br/>";
    return $$specs{Status} = 'uncalculated';
  } # end if

  my @possible_equipment;
  foreach my $Equipment ( @all_equipment ) {
    my $max_pages = $Equipment->specification('Stitching Maximum Pages', undef );
    $max_pages = $Equipment->specification('Maximum Pages', undef ) if ! $max_pages;
    if ( $max_pages and $$printing_specs{txtTotalPageQuantity} > $max_pages ) {
      $error .= "For " . $Equipment->name() . ": Only supports $max_pages pages.\n";
    } elsif ( my $reason = $Equipment->fits( @$printing_specs{'txtFinalWidth','txtFinalHeight'} ) ) {
      $error .= "For " . $Equipment->name() . ":\n". $reason  . "\n";
    } elsif ( $_ = $Equipment->Specification('Maximum Finished Calliper')
        and $$_{value} and
      ($$_{value} < $$specs{txtCalliper}) ) {
      my $reason  = "Project is too thick. Max Finished Calliper $$_{value} < $$specs{txtCalliper}\n";
      $error .= "For " . $Equipment->name() . ":\n". $reason  . "\n";
    } else {
      push @possible_equipment, $Equipment
    } # end if
  } # end foreach

  if ( ! @possible_equipment ) {
    # alert the user that no equipment is good.
    $$specs{alert} = "Our stitching equipment cannot run this project, for the following reasons:\n$error\n Please only print flat sheets and contact another bindery.";
  } # end if

  foreach my $qty_index ( $Project->quantity_indexes() ) {
    my %bestPrice;
    $$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};

    my $bestEquipment;

    my @equipment = ();
    if ( $$specs{"chkOverrideEquipment$qty_index"} eq 'Y' ) {
      if (!$$specs{"ddmEquipment$qty_index"}) {
        $$specs{alert} .= 'No equipment chosen for quantity '.$qty_index.'<br/>';
        next;
      }
      @equipment = ( new openprint::Equipment( $$specs{"ddmEquipment$qty_index"} ) );
    } else {
      @equipment = @possible_equipment;
    } # end if

    my $pockets = $$specs{"txtPockets$qty_index"} = 0;
    $pockets += int($$specs{txtInsertQuantity}) if $$specs{txtInsertQuantity};

    my $override_pockets = 0;
    if ((defined $$specs{'OverridePockets'.$qty_index}) and ($$specs{'OverridePockets'.$qty_index} eq 'Y')) {
      foreach my $pages ( @possible_pages ) {
        $pockets += $$specs{join('','txtSignatureQty',$pages,'Page-',$qty_index)};
      }
      $override_pockets = 1;
    } else {
      foreach my $pages ( @possible_pages ) {
        $$specs{'txtSignatureQty'.$pages.'Page-'.$qty_index} = 0;
      } # end foreach
      $$specs{"txtPockets$qty_index"} = 0;
    }
    my $max_imposition = 0;
    my $max_pages = 0;
    foreach my $sig_id (@signatures) {
      my $sig_specs = openprint::service::get_specs_ref($Project, $sig_id);
      $max_imposition = $$sig_specs{'txtImposition'.$qty_index} if $$sig_specs{'txtImposition'.$qty_index} > $max_imposition;
      $max_pages = $$sig_specs{'PageQuantity'.$qty_index} if $$sig_specs{'PageQuantity'.$qty_index} > $max_pages;
      if ( !$override_pockets ) {
        $$specs{join('','txtSignatureQty',$$specs{'PageQuantity'.$qty_index},'Page-',$qty_index)} += 1;
      }
    }

    foreach my $Equipment ( @equipment ) {

      my %price = {
        MakeReady => 0,
        Service	  => 0,
        txtPrice	=> 0,
        RunTime	  => 0,
      };

      $price{MakeReady} = openprint::service::get_price( $$specs{ServiceType}.'MakeReady', undef, $Equipment );
      $price{RunTime} += $Equipment->specification( 'Make Ready', undef );

      my $runspeed = $Equipment->Specification($$specs{ServiceType}.'Run Speed');
      $runspeed = $Equipment->Specification('Run Speed') if !$runspeed;
      $runspeed = $Equipment->Specification('Units Per Hour') if ! $runspeed;
      if (!$runspeed) {
        $$specs{alert} .= "No run speed set for $$Equipment{strid}<br/>";
        next;
      }
      if (($$runspeed{min} or $$runspeed{max}) and ! $$runspeed{range_units}) {
        $$specs{alert} .= "No run speed range units set for $$Equipment{strid}<br/>";
      } 
      if ( ($_=$Equipment->specification('Maximum CornerStitching Imposition')) and ($max_imposition > $_)) {
        $$specs{alert} .= 'For '. $Equipment->name().' Can only do '.$_.' out.<br/>';
        next;
      }
      if ( ($_=$Equipment->specification('Maximum CornerStitching Page Size')) and ($max_pages > $_)) {
        $$specs{alert} .= 'For '. $Equipment->name().' Can only do '.$_.' pages size.<br/>';
        next;
      }

      my $runtime = $$specs{"txtQuantity$qty_index"}/$$runspeed{value} if $runspeed and $$runspeed{value};
      my %servicePrice = openprint::service::get_price_object( $$specs{ServiceType}, undef, $Equipment );
      if ( $servicePrice{units} eq 'per m' ) {
        $price{Service} += $servicePrice{Price} * $$specs{'txtQuantity'.$qty_index}/1000;
      } elsif ( $servicePrice{units} eq 'per hour' ) {
        if (!$runtime) {
          $$specs{alert} .= "Unable to calculate runtime on $$Equipment{strid}.<br/>";
          next;
        }
        $price{Service} += $servicePrice{Price} * $runtime;
      } else {
        $log->debug("Unknown Unit Type: $servicePrice{units}");
      } # end if

      $price{txtPrice} = $price{MakeReady} + $price{Service};

      if ( ! $bestPrice{txtPrice} or $price{txtPrice} < $bestPrice{txtPrice} ) {
        $bestEquipment = $Equipment;
        %bestPrice = %price;
      } # end if
      $$specs{'hdnBreakdown'.$qty_index} .= 'Quantity: ' . $$specs{"txtQuantity$qty_index"} .
      ", Equipment: " . $Equipment->name() . "\n";
      $$specs{'hdnBreakdown'.$qty_index} .= 'Estimated Run Time: '. sprintf('%.1f', $price{RunTime} ) . ",\n";
      $$specs{'hdnBreakdown'.$qty_index} .= 'MakeReady: $' . sprintf( '%.2f', $price{MakeReady}).",\n";
      $$specs{'hdnBreakdown'.$qty_index} .= 'Service: $' . sprintf( '%.2f', $price{Service}).",\n";
      $$specs{'hdnBreakdown'.$qty_index} .= 'Total: $'. sprintf('%.2f', int($price{txtPrice}))."\n";
    } # end foreach
    if ( ! $bestEquipment ) {
      $status = 'uncalculated';
      $$specs{"ddmEquipment$qty_index"} = '';
    } else {
      $$specs{"ddmEquipment$qty_index"} = $bestEquipment->id();
    } # end if

    $$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, 
      ( $bestPrice{txtPrice}/$$specs{"txtQuantity$qty_index"} ) * (1+$Project->markup()/100) );
    $$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $bestPrice{txtPrice} * (1+$Project->markup()/100) );
    $$specs{"txtRunTime$qty_index"} = $bestPrice{RunTime};
  } # end foreach
  $log->debug("END CORNER STITCHING!!!!!!!");
  return $status;
} # end sub calc

sub summary {
} # end sub summary

1;
__END__
