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

package openprint::Estimating::Gluing;
use strict;
use warnings;

require sql;
require openprint::service;

# Stripping tends to be a manual process.  There are tools to help...
my %ServicePrices = (
  GluingMinimumCharge => { units => []},
  'GluingMakeReady' => { units => [ 'per hour' ] },
  'Gluing' => { units=> ['per hour', 'per lb','per m']},
);
my %Specifications = (
  'Gluing Capable' => { values=>['Y','N'] },
  'Gluing Overs' => {range_units => [ 'impressions' ], units=>['percent']},
  'Gluing MakeReadyTime' => { units => 'minutes' },
  'Gluing RunSpeed' => { units => 'inches per hour'},
  'RunSpeed' => { units => 'inches per hour'},
);

sub ServicePriceConfiguration {
  my $name = shift;
  return $ServicePrices{$name} if $ServicePrices{$name};
  foreach my $key (keys %ServicePrices) {
    return $ServicePrices{$key} if ($name =~ /$key/i);
  }
  return undef;
}

sub SpecificationConfiguration {
  my $name = shift;
  return $Specifications{$name} if $Specifications{$name};
  return undef;
}

	#'ServiceType',
	#'rdbGluingType',
my @variables = (
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'Markup1', 'Markup2', 'Markup3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'MPrice1', 'MPrice2', 'MPrice3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
	'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
  'hdnBreakdown1','hdnBreakdown2','hdnBreakdown3',
  'ddmEquipment1','ddmEquipment2','ddmEquipment3',
'complexity',
);

sub variables {
	my ( $p_id, $s_id, $old_specs, $specs ) = @_;
	my @v = @variables;
	my $Project = new openprint::Project( $p_id );
	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		push @v, ( "txtArea-$$sig_specs{SignatureIndex}","chkOverrideArea-$$sig_specs{SignatureIndex}", );
	} # end foreach signature
	return @v;
} # end sub variables

my @outputs = (
	'hdnBreakdown1', 'hdnBreakdown2', 'hdnBreakdown3',
	'txtPrice1', 'txtPrice2', 'txtPrice3',
	'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
  'ddmEquipment1','ddmEquipment2','ddmEquipment3',
);

sub get_outputs {
	return @outputs;
} # end sub get_output

my @no_outputs = (
	'ProjectIndex', 'ServiceIndex', 'txtQuantity1','txtQuantity2','txtQuantity3',
	'ServiceType',
	'OverridePrice1', 'OverridePrice2', 'OverridePrice3',
	'Markup1', 'Markup2', 'Markup3',
);

sub no_outputs {
	my ( $p_id, $s_id, $specs ) = @_;
	my @o = @no_outputs;

	my $Project = new openprint::Project( $p_id );
	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		push @o, ( "chkOverrideArea-$$sig_specs{SignatureIndex}", );
	} # end foreach signature
	return @o;
};

sub neccessary {
	my ( $log, $dbh, $project_index ) = @_;

	my $Project = new openprint::Project( $project_index );
    my $services = $Project->services();

    if ( $$services{NoBindery} ) {
        $log->debug(" ** Project is marked as No bindery, Cutting not needed ! ** ");
        return 0;
    } # end if

    if ( $Project->Type()->name() eq 'PresentationFolders' ) {
        return 1;
    } # end if
	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		if ( sets::isin( $$sig_specs{rdbTemplateType}, ['2Panel1Pocket','2Panel2Pocket','TriFoldDoublePocket'] ) ) {
			return 1;
		} # end if
	} # end foreach signature

	return 0;
} # end sub neccessary

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $status = 'calculated';

$log->debug("GLUING!!!!!!!!!!!!!!!!!!");

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
  my $Service = $Project->Service( $service_index );

	foreach ( @outputs ) {
		delete $$specs{$_};
	} # end foreach

	my $calliper = $Project->calliper();

	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
    my $form = $$sig_specs{SignatureIndex};
    my @complexityoptions = map { openprint::Service->find_one(name=>'Gluing'.$_) ? $_ : () } ( 'Simple','Average', 'Complex' );

		if ( (!$$specs{"chkOverrideArea-$form"}) or ($$specs{"chkOverrideArea-$form"} ne 'Y')) {
			$$specs{"txtArea-$form"} = 0;
      # Figure out square area of gluing
			if ( sets::isin( $$sig_specs{rdbTemplateType}, ['2Panel1Pocket','2Panel2Pocket','TriFoldDoublePocket'] ) ) {
				if ( $$sig_specs{chkPocketLeft}  and ($$sig_specs{chkPocketLeft} eq 'Left')) {
					$$specs{"txtArea-$form"} += .5 * $$sig_specs{PocketSize};
				} # end if
				if ( $$sig_specs{chkPocketRight} and ($$sig_specs{chkPocketRight} eq 'Right')) {
					$$specs{"txtArea-$form"} += .5 * $$sig_specs{PocketSize};
				} # end if
			} elsif ( $Project->Type()->name() eq 'ScratchPads' ) {
				$$specs{"txtArea-$form"} = $$sig_specs{txtWidth} * $calliper;
			} # end if
		} # end if

		if ( $$specs{"txtArea-$form"} eq '' ) {
			$$specs{help} = 'Please enter the area in square inches to be covered in glue.';
			return 'uncalculated';
		} # end if
    if (@complexityoptions and !$$specs{complexity}) {
      $$specs{help} .= 'Please select the complexity of the gluing.<br/>';
			return 'uncalculated';
    }
  }

  foreach my $qty_index ( $Project->quantity_indexes() ) {
    $$specs{"txtQuantity$qty_index"} = int( $$specs{"txtQuantity$qty_index"} );
    $$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
    next if ! $$specs{"txtQuantity$qty_index"};
    $$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"Markup$qty_index"};
    $$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtPrice$qty_index"};
    my $qty = $$specs{"txtQuantity$qty_index"};
    $$specs{"hdnBreakdown$qty_index"} = 'Project Calliper: '.$calliper.'<br/>';

    my $total = 0;
    my $unitPrice = 0;
    my $mprice = 0;

    foreach my $ss_id ( $Project->signatures() ) {
      my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );

      my $price = get_price($Project, $Service, $specs, $sig_specs, $qty_index);
      $total += $$price{Total};
      $mprice += $$price{MPrice};
      $$specs{"hdnBreakdown$qty_index"} .= $$price{Breakdown};
      $$specs{"ddmEquipment$qty_index"} .= $$price{Equipment}->id() if $$price{Equipment};
    } # end foreach signature

    if ( (!$$specs{"OverridePrice$qty_index"}) or ($$specs{"OverridePrice$qty_index"} ne 'Y')) {
      $total *= (1+$$specs{"Markup$qty_index"}/100) if $$specs{"Markup$qty_index"};
      $total *= (1+$Project->markup()/100) if $Project->markup();
      $mprice *= (1+$$specs{"Markup$qty_index"}/100) if $$specs{"Markup$qty_index"};
      $mprice *= (1+$Project->markup()/100) if $Project->markup();

      $unitPrice = $total / $qty;
    } else {
      $unitPrice = $$specs{"txtPrice$qty_index"} / $qty;
      $$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
    } # end if
    $$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $unitPrice);
    $$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $total);
    $$specs{"MPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $mprice);
  } # end foreach qty_index

	return $status;
} # end sub calc

sub get_price {
  my ($Project, $Service, $specs, $sig_specs, $qty_index) = @_;
  my $form = $$sig_specs{SignatureIndex};
  my %best_price = (
    MakeReady => undef,
    Minimum => 0,
    Service => undef,
    Equipment => undef,
    Breakdown => '',
    Total => 0,
    MPrice => 0,
  );


  my @Equipment;
  if ( (defined $$specs{"chkOverrideEquipment-$form-$qty_index"}) and ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) ) {
    @Equipment = ( new openprint::Equipment( $$specs{"ddmEquipment-$form-$qty_index"} ) );
  } else {
    @Equipment = openprint::Equipment->find( useinestimating=>1, 'servicetype_id any'=>$Service->servicetype_id() );
  } # end if
  foreach my $Equipment (@Equipment) {
    my %price = (
      MakeReady => undef,
      Total => 0,
      MPrice => 0,
      Minimum => 0,
      ServicePrice => undef,
      MaterialPrice => undef,
      Equipment => $Equipment,
      Breakdown => '',
    );

    $price{Breakdown} .= '<b>'.$Equipment->name().'</b><br/>';
    my $qty = $$specs{"txtQuantity$qty_index"};
    if ( my $Overs = $Equipment->Specification('Gluing Overs') ) {
      my $overs;
      if ( $$Overs{units} eq 'percent' ) {
        $overs = int( $qty * ($$Overs{value}/100) );
      } elsif ( $$Overs{units} eq 'sheets' ) {
        $overs = int( $$Overs{value} );
      } else {
        $price{Breakdown} .= "Unknown units $$Overs{units} in Gluing Overs<br/>";
        $openprint::log->error("Unknown units $$Overs{units} in Gluing Overs");
      } # end if
      $price{Overs} = $overs;
      $qty += $overs;
      $price{Breakdown} .= 'Overs '.$$Overs{value}.$$Overs{units}. ' = '.$overs.'<br/>';
    } # end if

    my $makeReadyPrice = openprint::service::get_price('GluingMakeReady', undef, $Equipment) || 0;
    my $minimumCharge = openprint::service::get_price('GluingMinimumCharge', undef, $Equipment) || 0;
    $price{Breakdown} .= 'MakeReady: $' . sprintf( '%.2f', $makeReadyPrice ? $makeReadyPrice : 0) . '<br/>';
    $price{Breakdown} .= 'MinimumCharge: $' . sprintf( '%.2f', $minimumCharge ? $minimumCharge : 0 ) . '<br/>';

    my %servicePrice = openprint::service::get_price_object( 'Gluing'.$$specs{complexity}, $qty, $Equipment );
    $price{ServicePrice} = \%servicePrice;
    if ($servicePrice{units}) {
      if ($servicePrice{units} eq 'per m' or $servicePrice{units} eq 'per 1000') {
        $servicePrice{Total} = $qty * $servicePrice{Price} / 1000;
        $price{MPrice} = $servicePrice{Price};
        $price{Breakdown} .= sprintf( 'Service: $%.2f %s = $%.2f<br/>', @servicePrice{'Price','units','Total'} );
      } elsif ( $servicePrice{units} eq 'per hour') {
        my $runspeed = $Equipment->Specification('Gluing RunSpeed');
        $runspeed = $Equipment->Specification('RunSpeed') if ! $runspeed;

        my $height = $$sig_specs{txtWidth} > $$sig_specs{txtHeight} ? $$sig_specs{txtHeight} : $$sig_specs{txtWidth};
        if (!$runspeed) {
          $openprint::log->error("No runspeed set for Gluing on $$Equipment{name}");
          $price{Breakdown} .= "No runspeed set for gluing. Can't support per hour pricing.<br/>";
        } elsif ($$runspeed{units} eq 'inches per hour') {
          $servicePrice{Total} = $qty * $height * $servicePrice{Price} / $$runspeed{value};
          $price{Breakdown} .= sprintf( 'Service: $%1$.2f %2$s * %6$d * %4$.2finches @ %5$d/hour= $%3$.2f<br/>', @servicePrice{'Price','units','Total'}, $height, $$runspeed{value}, $qty );
          $price{MPrice} = 1000 * $height * $servicePrice{Price} / $$runspeed{value};
        } else {
          $openprint::log->error("Unsupported units in $$runspeed{name} $$runspeed{units}");
          $price{Breakdown} .= "Unsupported units in $$runspeed{name} $$runspeed{units}<br/>";
        }
      } else {
        $openprint::log->error("Unsupported units in Gluing ($servicePrice{units})");
        $$specs{alert} .= "Unsupported units in Gluing ($servicePrice{units})<br/>";
      } # end if
    } else {
      $openprint::log->error("No units in Gluing ($servicePrice{units})");
      $$specs{alert} .= "No units in Gluing ($servicePrice{units})<br/>";
    } # end if
    $price{Total} = $makeReadyPrice + $servicePrice{Total};
    if ( my $Material = openprint::Material->find_one(name=>'Glue') ) {
      my %materialPrice = $Material->get_price( $$specs{"txtArea-$$sig_specs{SignatureIndex}"}, undef );
      $price{MaterialPrice} = \%materialPrice;
      if ( %materialPrice ) {
        $materialPrice{Total} = $materialPrice{Price} * $$specs{"txtArea-$$sig_specs{SignatureIndex}"} * $qty;
        $price{Breakdown} .= sprintf( 'Material: $%.2f %s * %.2f square inches * %d = $%.2f<br/>', @materialPrice{'Price','units'}, $$specs{"txtArea-$$sig_specs{SignatureIndex}"}, $qty, $materialPrice{Total} );
      } else {
        $price{Breakdown} .= 'No Material Price.<br/>';
      } # end if
      $price{Total} += $materialPrice{Total};
    } else {
      $price{Breakdown} .= 'No Material.<br/>';
    } # end if

    if ( $minimumCharge and ($price{Total} < $minimumCharge)) {
      $price{Total} = $minimumCharge;
    } # end if
    if (!$best_price{Total} or ($best_price{Total} > $price{Total})) {
      %best_price = %price;
    }
  } # end foreach equipment
  return \%best_price;
}

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;
	if ( $qty_index ) {
		return '';
	} # end if

	return '';
} # end sub summary

sub display {
} # end sub display

sub save {
} # end sub save

sub has_overrides {
    my ( $Project, $service_id, $specs, $qty_index ) = @_;
    $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

    my @v;
    if ( ! $qty_index ) {
    } else {
      push @v, map { $$specs{$_.$qty_index} ? $_.$qty_index : () } ( 'OverridePrice' );
    } # end if

    return @v;
} # end sub has_overrides

1;

__END__
