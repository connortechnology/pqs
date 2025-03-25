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

package openprint::Estimating::SpinePaste;
use strict;
#use warnings;

use constant DEBUG => 1;
require openprint::service;

use vars qw( %ServicePrices %Specifications);
%ServicePrices = (
  SpinePasteMinimumCharge => {},
  'SpinePasteMakeReady.*' => {},
  SpinePaste => { units=> ['per hour', 'per m']},
  SpinePasteTrimmingMakeReady => {},
  SpinePasteTrimming => {},

);
%Specifications = (
  'SpinePaste Runspeed' => {range_units => [ 'calliper'], units=>'per hour'},
  'SpinePaste MakeReady Overs' => {range_units => [ 'impressions' ], units=>['percent']},
  'SpinePaste Capable' => { value=>['Y','N'] },
  'SpinePasteTrimming MakeReady Time' => {},

);

sub ServicePriceConfiguration {
  return $ServicePrices{shift};
}
sub SpecificationConfiguration {
  return $Specifications{shift};
}


my @variables = (
		'chkOverrideCalliper',
		'txtCalliper',
		'Trimming','Gluing',
    'complexity',

		'ddmEquipment1', 'ddmEquipment2', 'ddmEquipment3',
		'chkOverrideEquipment1', 'chkOverrideEquipment2', 'chkOverrideEquipment3',
		'txtPrice1', 'txtPrice2', 'txtPrice3',
		'MPrice1', 'MPrice2', 'MPrice3',
		'txtUnitPrice1', 'txtUnitPrice2', 'txtUnitPrice3',
		'txtQuantity1', 'txtQuantity2', 'txtQuantity3',
		'txtRunTime1', 'txtRunTime2', 'txtRunTime3',
		'Runspeed1', 'Runspeed2', 'Runspeed3',
		'OverrideRunspeed1', 'OverrideRunspeed2', 'OverrideRunspeed3',
		);
sub variables {
  return @variables;
}

sub neccessary {
	my ( $Project ) = @_;

	my $services = $Project->services();

	if ( $$services{NoBindery} ) {
		$openprint::log->debug(" ** Project is marked as No bindery, Hand Assembly not needed ! ** ");
		return 0;
	} # end if

	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] ) if $$services{''} and $$services{''}[0];

	if ( $$printing_specs{rdbTemplateType} eq 'SpinePaste' ) {
		return 1;
	} # end if

	return 0;	
} # end sub neccessary

sub signature_calc {
	my ( $Project, $service_index, $I, $specs, $qty_index, $folding_results ) = @_;

	my $services = $Project->services();
	my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
	my @Equipment = openprint::Equipment->find( Specifications=>{'SpinePaste Capable'=>'Y'}, useinestimating=>1);
	my %Results;
	if ( ! @Equipment ) {
		$Results{Status} = 'uncalculated';
		$Results{alert} .= 'No equipment for Spine Pasting.<br/>';
		return \%Results;
	} # end if
	if ( $$specs{'chkOverrideEquipment'.$qty_index} eq 'Y' ) {
		if ( ! sets::isin( $$specs{'ddmEquipment'.$qty_index}, [ map { $_->id() } @Equipment ] ) ) {
			$Results{Status} = 'uncalculated';
			$Results{alert} .= 'Overriden equipment is not good for Spine Pasting<br/>';
			return \%Results;
		} # end if
		@Equipment = ( new openprint::Equipment( $$specs{'ddmEquipment'.$qty_index} ) );
	} # end if

	my %best;
	foreach my $Equipment ( @Equipment ) {
		if ( $Equipment->specification('Type') eq 'Press' ) {
# Inline pasting
			if ( $Equipment->id() != $I->Press()->id() ) {
				#$openprint::log->debug("Not printing on " . $Equipment->strid() . '<br/>' );
				next;
			} # end if
			if ( $Equipment->specification('SpinePaste Maximum Imposition') and $I->imposition() > $Equipment->specification('SpinePaste Maximum Imposition') ) {
				$openprint::log->debug('Imposition too large ' . $I->imposition() . '>' . $Equipment->specification('SpinePaste Maximum Imposition') . " for " . $Equipment->strid() .'<br/>' );
				next;
			} # end if
      my $max_pages = $Equipment->specification('SpinePaste Maximum Pages');
			if ($max_pages and ($I->pages() > $max_pages)) {
				$openprint::log->debug('Too many Pages ' . $I->pages() . '>' . $max_pages. ' for ' . $Equipment->strid() . '<br/>' );
				next;
			} # end if
			if ( $I->image_orientation() ne openprint::Imposition::Vertical ) {
				$openprint::log->debug('Can only spine paste a vertical spine. <br/>' );
				next;
			} # end if
			if ( ! $service_index ) {
				$openprint::log->debug('Can only spine paste 1 signature for ' . $Equipment->strid() . '<br/>' );
				next;
			} # end if
			my $sigs = 1;
			foreach my $ss_id ( $Project->signatures() ) {
				$sigs += 1 if ( $ss_id < $service_index );
			} # end foreach
			if ( $sigs > 1 ) {
				$openprint::log->debug('Can only spine paste 1 signature for ' . $Equipment->strid() . '<br/>' );
				next;
			} # end if
			if ( ( ! $$folding_results{Equipment} ) or ( $$folding_results{Equipment}->id() != $Equipment->id() ) ) {
				$openprint::log->debug( "Must also be folded on $$Equipment{strid}.");
				next;
			} # end if
		} # end if
		my %Price = calc_price( $qty_index, $$specs{'txtQuantity'.$qty_index}, $Equipment, $I->pages(), $I->imposition(), $$folding_results{RunSpeed}, $services, $specs );
		if ( (!defined $best{Price}) or ($Price{Total} < $best{Price}{Total}) ) {
			$best{Price} = \%Price;
			$best{Equipment} = $Equipment;
		} # end if
	} # end foreach Equipment
	if ( ! %best ) {
		$Results{Status} = 'uncalculated';
		$Results{alert} .= 'Unable to calculate.<br/>';
	} else {
		$Results{Status} = 'calculated';
		$Results{Equipment} = $best{Equipment};
		$Results{Price} = $best{Price}{Total};
		$Results{RunSpeed} = $best{Price}{RunSpeed};
		$Results{MakeReadyTime} = $best{Price}{MakeReadyTime};
		$Results{MakeReadyOvers} = $best{Price}{MakeReadyOvers};
	} # end if
	return \%Results;
} # end sub signature_calc

sub calc {
	my ( $log, $dbh, $variable, $project_index, $service_index, $specs ) = @_;

	my $Project = new openprint::Project( $project_index );

	if ( $Project->signatures() > 1 ) {
		$$specs{alert} .= 'Spine Pasting requires there to be only 1 signature.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my @Equipment = openprint::Equipment->find('Specifications'=>{'SpinePaste Capable'=>'Y'});
	if ( ! @Equipment ) {
		$$specs{alert} .= 'We are unable to automatically provide a price for Spine Pasting.  You may enter your own price in the price fields, or contact your CSR for a quote.';

		foreach my $qty_index ( $Project->quantity_indexes() ) {
			$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
			my $qty = $$specs{'txtQuantity'.$qty_index};
			if ( $qty and ! $$specs{'txtPrice'.$qty_index} ) {
				return $$specs{Status} = 'calculated';
			} # end if
		} # end foreach
		
		return $$specs{Status}='uncalculated';
	} # end if

	if ( $$specs{chkOverrideCalliper} ne 'Y' ) {
		$$specs{txtCalliper} = openprint::print::get_finished_calliper( $project_index );
	} # end if

	my $services = $Project->services();
	if ( ! ($$services{Folding} and @{$$services{Folding}} ) ) {
		$$specs{alert} .= 'Project does not have a folding service.  Folding is required.<br/>';
		return $$specs{Status} = 'uncalculated';
	} # end if
	my $folding_specs = openprint::service::get_specs_ref( $Project, $$services{Folding}[0] );
	my $pages = 0;
	if ( $$services{''} ) {
		my $printing_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
		$pages = $$printing_specs{txtTotalPageQuantity};
	} # end if
	my @sigs = $Project->signatures();

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{"Markup$qty_index"} =~ s/[^\d\.\-]//g if $$specs{"Markup$qty_index"};
		$$specs{"txtPrice$qty_index"} =~ s/[^\d\.]//g if $$specs{"txtPrice$qty_index"};
		$$specs{"txtQuantity$qty_index"} = $Project->quantity($qty_index) if ! $$specs{"txtQuantity$qty_index"};
		my $qty = $$specs{'txtQuantity'.$qty_index};

		# Indexed by service_id
		my %impositions;

		my $imposition = 0;
		foreach my $ss_id ( @sigs ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );

			my $I = $impositions{$ss_id} = new openprint::Imposition();
			$I->load( $sig_specs, $qty_index, $Project );	
			$imposition = $$I{imposition} if $$I{imposition} < $imposition;
		} # end foreach

		my %best;
		my $sig_specs = openprint::service::get_specs_ref( $Project, $sigs[0] );
		my $I = $impositions{$sigs[0]};

		if ( $$specs{'chkOverrideEquipment'.$qty_index} eq 'Y' ) {
			if ( ! sets::isin( $$specs{'ddmEquipment'.$qty_index}, [ map { $_->id() } @Equipment ] ) ) {
				$$specs{alert} .= 'Overriden equipment s not good for Spine Pasting<br/>';
				$$specs{Status} = 'uncalculated';
				next;
			} # end if
		} # end if

		foreach my $Equipment ( $$specs{'chkOverrideEquipment'.$qty_index} eq 'Y' ? ( new openprint::Equipment( $$specs{'ddmEquipment'.$qty_index} ) ) : @Equipment ) {
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Equipment: %s %s<br/>', $Equipment->strid(), $Equipment->name() );

			if ($Equipment->specification('Type') eq 'Press') {
        # Inline pasting
				if ( @sigs > 1 ) {
					$openprint::log->debug('Can only spine paste 1 signature for ' . $Equipment->strid() );
					next;
				} # end if
				if ( $Equipment->strid() ne $$sig_specs{'ddmPress'.$qty_index} ) {
					$$specs{'hdnBreakdown'.$qty_index} .= 'Not printing on ' . $Equipment->strid().'<br/>';
					next;
				} # end if
				if ( $Equipment->specification('SpinePaste Maximum Imposition') and $I->imposition() > $Equipment->specification('SpinePaste Maximum Imposition') ) {
					$$specs{'hdnBreakdown'.$qty_index} .= "Imposition too large " . $I->imposition() . '>' . $Equipment->specification('SpinePaste Maximum Imposition') . " for " . $Equipment->strid() . '<br/>';
					next;
				} # end if
				if ( $Equipment->specification('SpinePaste Maximum Pages') and $Equipment->specification('SpinePaste Maximum Pages') and $I->pages() > $Equipment->specification('SpinePaste Maximum Pages') ) {
					$$specs{'hdnBreakdown'.$qty_index} .= "Too many pages for " . $Equipment->strid() . '<br/>';
					next;
				} # end if
				if ( $I->image_orientation() ne openprint::Imposition::Vertical ) {
					$$specs{'hdnBreakdown'.$qty_index} .= 'Can only spine paste a vertical spine. <br/>';
					next;
				} # end if
				my %folding_results;
				$folding_results{Equipment} = new openprint::Equipment( $$folding_specs{"ddmEquipment-$$sig_specs{SignatureIndex}-$qty_index"} );
				if ( $folding_results{Equipment}->id() and ($folding_results{Equipment}->id() != $Equipment->id())) {
					$$specs{'hdnBreakdown'.$qty_index} .= 'Must also be folded on ' . $Equipment->strid() . '<br/>';
					next;
				} # end if
				$imposition = $I->imposition();
			} # end if is a Press
			my $folding_runspeed = 0;
			foreach my $fold_index ( 1 .. 4 ) {
				$folding_runspeed = $$folding_specs{"FoldRunspeed-$$sig_specs{SignatureIndex}-$qty_index-$fold_index"};
				last if $folding_runspeed;
			} # end foreach fold_index

			my %Price = calc_price( $qty_index, $qty, $Equipment, $pages, $imposition, $folding_runspeed, $services, $specs );
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('QTY %d Folding max run speed %d/hr Spine Paste Run Speed: %d/hr<br/>', $qty, $folding_runspeed, $Price{RunSpeed} );
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('MakeReady: $%.2f<br/>', $Price{MakeReady}{Price} );
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('MakeReadyTime: %dminutes<br/>', $Price{MakeReadyTime} );
      $$specs{'hdnBreakdown'.$qty_index} .= sprintf('MakeReady Overs: %d<br/>', $Price{MakeReadyOvers} );
      if ( $$specs{Gluing} ne 'N' ) {
        $$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service Price: $%.2f%s for %d = $%.2f<br/>', $Price{ServicePrice}{Price},$Price{ServicePrice}{units},$qty, $Price{ServicePrice}{Total} );
      }
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Trimming Price: $%.2f%s for %d = $%.2f<br/>', $Price{TrimmingPrice}{Price},$Price{TrimmingPrice}{units},$qty, $Price{TrimmingPrice}{Total} );
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Trimming MakeReady: $%.2f<br/>', $Price{TrimmingMakeReady}{Price} );
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Trimming MakeReady Time: %dminutes<br/>', $Price{TrimmingMakeReadyTime} );
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Total: $%.2f<br/>', $Price{Total} );

			if ( (!defined $best{Price}) or $Price{Total} < $best{Price}{Total} ) {
				$best{Price} = \%Price;
				$best{Equipment} = $Equipment;
			} # end if
		} # end foreach Equipment

		if ( ! %best ) {
			$$specs{'Runspeed'.$qty_index} = '' if $$specs{'OverrideRunspeed'.$qty_index} ne 'Y';
			$$specs{'ddmEquipment'.$qty_index} = '';
			$$specs{"txtPrice$qty_index"} = '';
			$$specs{"MPrice$qty_index"} = '';
			$$specs{"txtUnitPrice$qty_index"} = '';
			$$specs{Status} = 'uncalculated';
			$$specs{alert} = 'Unable to calculate.<br/>';
		} else {
			$$specs{'Runspeed'.$qty_index} = $best{Price}{RunSpeed} if !$$specs{'OverrideRunspeed'.$qty_index} or ($$specs{'OverrideRunspeed'.$qty_index} ne 'Y');
			$$specs{'ddmEquipment'.$qty_index} = $best{Equipment}->id();

      if ($$specs{"Markup$qty_index"}) {
        $best{Price}{Total} *= (1+$$specs{"Markup$qty_index"}/100);
        $best{Price}{MPrice} *= (1+$$specs{"Markup$qty_index"}/100);
        $best{Price}{ServicePrice}{Total} *= (1+$$specs{"Markup$qty_index"}/100);
      }
      if ($Project->markup()) {
        $best{Price}{Total} *= (1+$Project->markup()/100);
        $best{Price}{MPrice} *= (1+$Project->markup()/100);
        $best{Price}{ServicePrice}{Total} *= (1+$Project->markup()/100);
      }

			if ( (!$$specs{"OverridePrice$qty_index"}) or ($$specs{"OverridePrice$qty_index"} ne 'Y')) {
				$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $best{Price}{Total});
			} else {
				$$specs{"txtPrice$qty_index"} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
			} # end if
			$$specs{"MPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $best{Price}{MPrice});
			$$specs{"txtUnitPrice$qty_index"} = sprintf( $openprint::config{UnitPriceFormat}, $best{Price}{ServicePrice}{Total} / $qty);
			$$specs{Status} = 'calculated';
		} # end if
  } # end foreach qty_index

	$log->debug(" END Spine Paste!!!!!!!!!!!!!!!!! Status: $$specs{Status}");
	return $$specs{Status};
} # end sub calc

# runspeed passed in s folding run speed.
sub calc_price {
	my ( $qty_index, $qty, $Equipment, $pages, $imposition, $runspeed, $services, $specs ) = @_;
	my %Price;
	my %MakeReady;
	my %ServicePrice;
	$Price{RunSpeed} = $runspeed;

	if ( ! ( %MakeReady = openprint::service::get_price_object( 'SpinePasteMakeReady'.$pages.'Page'.$imposition.'out', $qty, $Equipment ) ) ) {
		if ( ! ( %MakeReady = openprint::service::get_price_object( 'SpinePasteMakeReady'.$pages.'Page', $qty, $Equipment ) ) ) {
			%MakeReady = openprint::service::get_price_object( 'SpinePasteMakeReady', $qty, $Equipment );
		} # end if
	} # end if
	$Price{MakeReady} = \%MakeReady;
	$Price{MakeReadyTime} = $Equipment->specification('SpinePaste MakeReady Time') || 0;
  $Price{MakeReadyOvers} = $Equipment->specification('SpinePaste MakeReady Overs') || 0;

	$Price{MPrice} = 0;

	if ( $$specs{Gluing} ne 'N' ) {
		$openprint::log->debug("Starting Runspeed $runspeed ");
		if ( $$specs{'OverrideRunspeed'.$qty_index} and ($$specs{'OverrideRunspeed'.$qty_index} eq 'Y')) {
			$Price{'Gluing RunSpeed'} = $$specs{'Runspeed'.$qty_index};
		} elsif ( ( my $RunSpeed = $Equipment->Specification('SpinePaste RunSpeed') ) ) {
			if ( $RunSpeed->units() eq 'Percent' ) {
				$Price{'Gluing RunSpeed'} = $runspeed * ( 1 + $RunSpeed->value()/100 );
      } elsif ($RunSpeed->units() eq 'impressions') {
        $RunSpeed = $Equipment->Specification('SpinePaste RunSpeed', $qty);
        $Price{'Gluing RunSpeed'} = $RunSpeed->value();
			} else {
        $openprint::log->error("No units set on SpinePaste RunSpeed on $$Equipment{name}");
				$Price{'Gluing RunSpeed'} = $RunSpeed->value();
			} # end if
      $Price{RunSpeed} = $Price{'Gluing RunSpeed'} if $Price{RunSpeed} > $Price{'Gluing RunSpeed'};
      $openprint::log->debug("Gluing runspeed $Price{'Gluing RunSpeed'}");
		} else {
			$openprint::log->debug('No Runspeed set');
		} # end if Runspeed
		if ( ( my $MaxRunSpeed = $Equipment->specification('SpinePaste Maximum RunSpeed') ) ) {
			$Price{'Gluing RunSpeed'} = $MaxRunSpeed;
		} # end if Maximum Run Speed
		#$openprint::log->debug("Runspeed is " . $Price{RunSpeed});
		if ( ! ( %ServicePrice = openprint::service::get_price_object( 'SpinePaste'.$pages.'Pages'.$imposition.'out', $qty, $Equipment ) ) ) {
			if ( ! ( %ServicePrice = openprint::service::get_price_object( 'SpinePaste'.$pages.'Pages', $qty, $Equipment ) ) ) {
				%ServicePrice = openprint::service::get_price_object( 'SpinePaste', $qty, $Equipment );
			} # end if
		} # end if
		if ( $ServicePrice{units} eq 'per m' ) {
			$ServicePrice{Total} = $ServicePrice{Price} * $qty / 1000;
    } else {
      $openprint::log->error('Unknown units on SpinePaste');
		} # end if
		$Price{ServicePrice} = \%ServicePrice;
		$Price{Total} = $MakeReady{Price} + $ServicePrice{Total};
		$Price{MPrice} += ( $ServicePrice{Total} / $qty ) * 1000;
	} # end if

	if ( $$specs{Trimming} ne 'N' ) {
    $Price{TrimmingMakeReadyTime} = $Equipment->specification('SpinePasteTrimming MakeReady Time') || 0;
		my %TrimmingMakeReady;
		if ( %TrimmingMakeReady = openprint::service::get_price_object( 'SpinePasteTrimmingMakeReady', undef, $Equipment ) ) {
			$Price{TrimmingMakeReady} = \%TrimmingMakeReady;
			$Price{Total} += $TrimmingMakeReady{Price};
		} # end if
		my %TrimmingPrice;
		if (%TrimmingPrice = openprint::service::get_price_object('SpinePasteTrimming', $qty, $Equipment)) {
			$Price{TrimmingPrice} = \%TrimmingPrice;
			$TrimmingPrice{Price} -= $ServicePrice{Price};
			if ( $TrimmingPrice{units} eq 'per m' ) {
				$TrimmingPrice{Total} = $TrimmingPrice{Price} * $qty / 1000;
      } else {
				$TrimmingPrice{Total} = $TrimmingPrice{Price};
			} # end if
			$Price{Total} += $TrimmingPrice{Total};
			$Price{MPrice} += ( $TrimmingPrice{Total} / $qty ) * 1000;
		} # end if
		if ( $$specs{'OverrideRunspeed'.$qty_index} and ($$specs{'OverrideRunspeed'.$qty_index} eq 'Y')) {
			$Price{'Trimming RunSpeed'} = $$specs{'Runspeed'.$qty_index};
		} elsif ( ( my $RunSpeed = $Equipment->Specification('Trimming RunSpeed') ) ) {
			if ( $RunSpeed->units() eq 'Percent' ) {
				$Price{'Trimming RunSpeed'} = $runspeed * ( 1 + $RunSpeed->value()/100 );
			} elsif ( $RunSpeed->value() < $runspeed ) {
				$Price{'Trimming RunSpeed'} = $RunSpeed->value();
			} else {
				$Price{'Trimming RunSpeed'} =  $runspeed;
			} # end if
		} else {
			$openprint::log->debug('No Runspeed set for Trimming');
		} # end if Runspeed
		if ( ( my $MaxRunSpeed = $Equipment->specification('Trimming Maximum RunSpeed') ) ) {
			$Price{'Trimming RunSpeed'} = $MaxRunSpeed if $Price{'Gluing RunSpeed'} and $Price{'Gluing RunSpeed'} > $MaxRunSpeed;
      $openprint::log->debug('Runspeed is ' . $Price{'Trimming RunSpeed'});
		} # end if Maximum Run Speed
		if ( $Price{'Trimming RunSpeed'} and ( ( ! $Price{RunSpeed} ) or ( $Price{'Trimming RunSpeed'} < $Price{RunSpeed} ) ) ) {
			$Price{RunSpeed} = $Price{'Trimming RunSpeed'};
		} #  end if
	} # end if
	return %Price;
} # end sub calc_price

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	if ( $qty_index ) {
		return '';
	} # end if
	my $html = 'Paste' if $$specs{Trimming} ne 'N';
	if ( $$specs{Gluing} ne 'N' ) {
		$html .= ' + ' if $html;
		$html .= 'Trim' 
	} # end if
	return $html;
} # end sub summary

sub display {
    my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	my $Project = new openprint::Project( $project_index );
    my @equipment = openprint::Equipment->find( Specifications=>{'SpinePaste Capable'=>'Y'}, useinestimating=>1, order=>'strName');
    foreach my $qty_index ( $Project->quantity_indexes() ) {
        $$variable{'Equipment'.$qty_index} = ssi::make_drop_down( [ map { $_->id(), $_->name() } @equipment ], $$variable{'ddmEquipment'.$qty_index} );
    } # end foreach qty_index

} # end sub display

sub has_overrides {
  my ( $Project, $service_id, $specs, $qty_index ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

  my @v;
  if ( $qty_index ) {
    push @v, "chkOverrideEquipment$qty_index" if $$specs{"chkOverrideEquipment$qty_index"};
    push @v, "OverrideRunspeed$qty_index" if $$specs{"OverrideRunspeed$qty_index"};
    push @v, "OverridePrice$qty_index" if $$specs{"OverridePrice$qty_index"};
	} else {
		push @v, 'chkOverrideCalliper' if $$specs{chkOverrideCalliper};
  } # end if

  return @v;

} # end sub has_overrides

1;
__END__
