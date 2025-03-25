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
package openprint::Estimating::Numbering;
use strict;

require openprint::service;
require openprint::Project;
use POSIX           qw(ceil);

use constant DEBUG => 1;

use vars qw( %ServicePrices %Specifications);
%ServicePrices = (
  NumberingMinimumCharge => {},
  NumberingMakeReady => {},
  Numbering => { units=> ['per hour', 'per m']},
);
%Specifications = (
  RunSpeed => {range_units => ['calliper','impressions'], units=>'per hour'},
  'Numbering Capable' => { value=>['Y','N','When Printing'] },
  'Numbering Heads' => {},
  'Numbering Colours' => {},
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
  return $Specifications{shift};
}

my %variables = (
    'alert' => ['save','output'],
	'SetsOfNumbers' => ['save'],
	'colour'		=> ['save'],
	'OverridePrice1' => ['save'], 'OverridePrice2' => ['save'], 'OverridePrice3' => ['save'],
	'Markup1' => ['save'], 'Markup2' => ['save'], 'Markup3' => ['save'],
	'txtPrice1' => ['save','output'], 'txtPrice2' => ['save','output'], 'txtPrice3' => ['save','output'],
	'MPrice1'	=> ['save','output'], 'MPrice2'	=> ['save','output'], 'MPrice3'	=> ['save','output'], 
	'txtQuantity1' => ['save'], 'txtQuantity2' => ['save'], 'txtQuantity3' => ['save'],
	'hdnBreakdown1' => ['save'], 'hdnBreakdown2' => ['save'], 'hdnBreakdown3' => ['save'],
);

sub variables {
	my ( $pid, $sid, $old_specs, $specs ) = @_;
  my @v;
  foreach my $k ( keys %variables ) {
    push @v, $k if sets::isin( 'save', $variables{$k} );
  } # end foreach;
	my $Project = new openprint::Project( $pid );
	foreach my $ss_id ( $Project->signatures() ) {
		foreach my $qty_index ( $Project->quantity_indexes() ) {
			push @v, "ddmEquipment-$ss_id-$qty_index", "chkOverrideEquipment-$ss_id-$qty_index",
					"txtImposition-$ss_id-$qty_index", "chkOverrideImposition-$ss_id-$qty_index",
		} # end foreach
	} # end foreach my ss_id
  return @v;
} # end sub variables

sub no_outputs {
	my ( $pid, $sid, $specs ) = @_;
  my @v;
  foreach my $k ( keys %variables ) {
    push @v, $k if ! sets::isin( 'output', $variables{$k} );
  } # end foreach;
  return @v;
} # end sub no_outputs

sub has_overrides {
  my ( $Project, $service_id, $specs, $qty_index ) = @_;
  $specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;

  my @v;
  foreach my $ss_id ( $Project->signatures() ) {
    foreach my $qty_index ( $Project->quantity_indexes() ) {
      foreach my $var ('chkOverrideEquipment', 'chkOverrideImposition') {
        my $v = join('-',$var, $ss_id, $qty_index);
        push @v,$v if $$specs{$v} and $$specs{$v} eq 'Y';
      }
    } # end foreach
  } # end foreach my ss_id
  if ( $qty_index ) {
    push @v, map { $$specs{$_.$qty_index} ? $_.$qty_index : () } ( 'OverridePrice' );
  } # end if

  return @v;
} # end sub has_overrides

sub calc {
  my ($log, $dbh, $variable, $pid, $sid, $specs) = @_;

	my $Project = new openprint::Project( $pid );
  my $Service = $Project->Service($sid);

  $$specs{alert} = '';
	$$specs{Status} = 'calculated';
	$$specs{SetsOfNumbers} =~ s/\D//g;
	if ( ! $$specs{SetsOfNumbers} ) {
		$$specs{alert} = 'Please enter the # of sets of numbers.';
		return $$specs{Status} = 'uncalculated';
	} # end if
	if ( ! $$specs{colour} ) {
		$$specs{alert} = 'Please select the colour of the numbers.';
		return $$specs{Status} = 'uncalculated';
	} # end if
	foreach my $qty_index ( $Project->quantity_indexes() ) {
		if ( $$specs{"OverridePrice$qty_index"} eq 'Y' ) {
			$$specs{"txtPrice$qty_index"} =~ s/[^\d\.\-]//g;
		} else {
			$$specs{"txtPrice$qty_index"} = 0;
			$$specs{"txtUnitPrice$qty_index"} = 0;
			$$specs{"MPrice$qty_index"} = 0;
		} # end if
		$$specs{'txtQuantity'.$qty_index} = $Project->quantity( $qty_index ) if ! $$specs{'txtQuantity'.$qty_index};
		foreach my $ss_id ( $Project->signatures() ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
			my $form = $$sig_specs{SignatureIndex};
			next if ! $$sig_specs{"txtImposition$qty_index"};

			my $Imposition = new openprint::Imposition()->load( $sig_specs, $qty_index, $Project );
			my $Results = signature_calc( $Project, $Service, $specs, $sig_specs, $qty_index, $Imposition );
			if ( ! $Results ) {
				$$specs{alert} .= 'No result from signature_calc.';
				$$specs{Status} = 'uncalculated';
				last;
			} # end if
# FIXME
			foreach my $Price ( @{$$Results{Prices}} ) {
				$$Results{UnitPrice} += ($$Price{ServicePrice}{Total} + $$Price{LastServicePrice}{Total} ) / $$specs{'txtQuantity'.$qty_index};
			} # end foreach Price
		
			$$specs{'hdnBreakdown'.$qty_index} .= $$Results{Breakdown};
			if ( $$Results{Equipment} ) {
				$$specs{"ddmEquipment-$form-$qty_index"} = $$Results{Equipment}->id();
$openprint::log->debug("Equipment is : " . $$Results{Equipment}->to_string() );
			} else {
				$openprint::log->error("NO Equipment in results!");
			} # end if Equipment
			if ( $$Results{Impositions} and (@{$$Results{Impositions}} == 1)) {
				$$specs{"txtImposition-$form-$qty_index"} = $Imposition->imposition();
				$$specs{"txtLayoutWidth-$form-$qty_index"} = $Imposition->layout_width();
				$$specs{"txtLayoutHeight-$form-$qty_index"} = $Imposition->layout_height();
			} else {
				# FIXME
				$$specs{"txtImposition-$form-$qty_index"} = '';
				$$specs{"txtLayoutWidth-$form-$qty_index"} = '';
				$$specs{"txtLayoutHeight-$form-$qty_index"} = '';
			} # end if
			if ( $$Results{Status} eq 'uncalculated' ) {
				$$specs{Status} = 'uncalculated';
				$$specs{alert} .= $$Results{alert};
				last;
			} # end if

			$$specs{'txtPrice'.$qty_index} += $$Results{Total};
			$$specs{'txtUnitPrice'.$qty_index} += $$Results{UnitPrice};
			$$specs{'MPrice'.$qty_index} += $$Results{MPrice};
		} # end foreach signature

		my $markup = $$specs{"Markup$qty_index"} ? $$specs{"Markup$qty_index"} : 0;

		$$specs{'txtUnitPrice'.$qty_index} = sprintf($openprint::config{UnitPriceFormat}, $$specs{'txtUnitPrice'.$qty_index} * (1+$Project->markup()/100) );
		$$specs{'MPrice'.$qty_index} = $$specs{'Markup'.$qty_index} ? sprintf( $openprint::config{UnitPriceFormat}, $$specs{'MPrice'.$qty_index}*(1+$markup/100)*(1+$Project->markup()/100) ) : '0.00';
		if ( $$specs{"OverridePrice$qty_index"} ne 'Y' ) {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{'txtPrice'.$qty_index}*(1+$markup/100)*(1+$Project->markup()/100) );
		} else {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{"txtPrice$qty_index"} );
		} # end if
  } # end foreach qty_index
	return $$specs{Status};

} # end sub calc

sub signature_calc {
	my ( $Project, $Service, $specs, $sig_specs, $qty_index, $Imposition ) = @_;

	my %Results;
	my $services = $Project->services();

	$$specs{'txtQuantity'.$qty_index} = $Project->quantity($qty_index) if ! $$specs{'txtQuantity'.$qty_index};

	my $form = $$sig_specs{SignatureIndex};
  if ( $$specs{"chkOverrideImposition-$form-$qty_index"} eq 'Y' ) {
    if ( $$specs{"txtImposition-$form-$qty_index"} > $Imposition->imposition() or $$specs{"txtImposition-$form-$qty_index"} <= 0 ) {
      $Results{alert} = 'The specified imposition is not possible.<br/>';
      $Results{Status} = 'uncalculated';
      return \%Results;
    } # end if
  } # end if

	my @Sets_Of_Impositions = ( [ $Imposition ] );

	my @Equipment;
	if ( $$specs{"chkOverrideEquipment-$form-$qty_index"} eq 'Y' ) {
		@Equipment = ( new openprint::Equipment($$specs{"ddmEquipment-$form-$qty_index"}) );
	} else {
		@Equipment = openprint::Equipment->find(
        useinestimating=>1,
        'servicetype_id any'=>$Service->servicetype_id(),
# 'Specifications'=>{'Numbering Capable'=>['Y','When Printing']},
        );
	} # end if
	if ( ! @Equipment ) {
		$Results{alert} .= 'We have no numbering equipment.';
		$Results{Status} = 'uncalculated';
		return \%Results;
	} # end if

	$Results{Status} = 'calculated';

	my @side_one_colours = openprint::Estimating::Printing::get_colours( $sig_specs, 'SideOne' );
	$openprint::log->debug("@side_one_colours : " . ( sets::intersection( 'Cyan','Magenta','Yellow','Black', @side_one_colours ) ) ) if DEBUG;
	my $Press = $Imposition->Press();
#$openprint::log->debug("Got press $Press for " . $$sig_specs{"ddmPress$qty_index"});
	if ( ! $Press ) {
		$Results{alert} .= 'No press.';
		$Results{Status} = 'uncalculated';
		return \%Results;
	} # end if
	my $Paper = $Imposition->Paper();

Equipment: foreach my $Equipment ( @Equipment ) {
		if ( $Equipment->specification('Numbering Capable') eq 'When Printing' ) {
			next if $$Press{id} != $Equipment->id();
		} # end if
		my $heads = $Equipment->specification('Numbering Heads');
		my %colours = map { $_, $_ } split(',', $Equipment->specification('Numbering Colours') );
		$Results{Breakdown} .= '<fieldset><legend>'.$Equipment->name().'</legend>';
		$Results{Breakdown} .= sprintf('Heads: %s<br/>',$heads);
		$Results{Breakdown} .= sprintf('Colours: %s<br/>', join(', ', keys %colours ) );

		if ( %colours and ! $colours{ $$specs{colour} } ) {
			$Results{Breakdown} .= $$specs{colour} . ' not in supported colours.<br/></fieldset>';
			next;
		} # end if

ImpositionSet: for ( my $set_index = 0; $set_index < @Sets_Of_Impositions; $set_index += 1 ) {
			my $Impositions = $Sets_Of_Impositions[$set_index];
			my %SetPrice;
			my $complete = 1;

      for ( my $imp_index = 0; $imp_index < @$Impositions; $imp_index += 1 ) {
        my $I = $$Impositions[$imp_index];
				if ( ! ( $I and $I->imposition() ) ) {
					$openprint::log->error("No imposition in Numbering.");
					$I->display();
					next ImpositionSet;
				}

				my $Breakdown = '';

				my $runs;
				my $last_run;
				$Breakdown .= sprintf('<b>Imposition: %dx%d=%dout</b><br/>', $I->get('columns','rows','imposition') ); 

				if ( $Equipment->id() == $Press->id() and $I->imposition() == $Imposition->imposition() ) {
					$Breakdown .= 'Numbering while printing.<br/>';
					$openprint::log->debug("@side_one_colours : " . ( sets::intersection( 'Cyan','Magenta','Yellow','Black', @side_one_colours ) ) );
					if ( ! ( 
								sets::isin( $$specs{colour}, \@side_one_colours ) or 
								( 4 == sets::intersection( 'Cyan','Magenta','Yellow','Black', @side_one_colours ) )
						   ) ) {
						$last_run = $$specs{SetsOfNumbers} * $I->imposition();
					} # end if
				} else {
# Check calliper separately, so that we don't cut down
					if ( $_ = $Equipment->specification('Maximum Calliper') and ( $$Paper{calliper} > $_ ) ) {
						$Breakdown .= "Too thick Max: $_, Stock: " . $$Paper{calliper} . '<br/>';
						$last_run = $$specs{SetsOfNumbers};
						next Equipment;
					} # end if
					if ( $_ = $Equipment->fits( $I->layout_width(), $I->layout_height() ) ) {
						$Breakdown .= "$_<br/>";
						$last_run = $$specs{SetsOfNumbers};
						if ( $$services{Cutting} ) {
# If we are the last set
							if ( $set_index+1 == @Sets_Of_Impositions ) {
								my @new_imps = @$Impositions;
                my @cuts = openprint::imposition::cut( $new_imps[$imp_index] );
                if ( @cuts ) {
                  splice @new_imps, $imp_index, 1, @cuts;
                  push @Sets_Of_Impositions, \@new_imps;
                }
							} # end if
						} else {
							$Breakdown .= 'Cant cut down W&T because no cutting.  Please add cutting.<br/>';
						} # end if
						next ImpositionSet;	
					} # end if

					if ( $heads ) {
						$runs = int($$specs{SetsOfNumbers} / $heads);
						$last_run = $$specs{SetsOfNumbers} % $heads;
					} else {
						$last_run = $$specs{SetsOfNumbers};
					} # end if
				} # end if

				my %ImpPrice;
				my $total = 0;
				my $mprice = 0;
				my $qty = ceil($$specs{'txtQuantity'.$qty_index} / $I->imposition());

				my %MakeReady = openprint::service::get_price_object('NumberingMakeReady', undef, $Equipment );
				if ( ! %MakeReady ) {
					$Breakdown .= 'No MakeReady price.<br/>';
				} else {
					$total += $MakeReady{Price};
					$Breakdown .= sprintf('MakeReady Price: $%1$.2f%2$s<br/>', @MakeReady{'Price','units'} );
				} # end if

				my %HeadMakeReady = openprint::service::get_price_object('NumberingHeadMakeReady', undef, $Equipment );
				if ( ! %HeadMakeReady ) {
					$Breakdown .= 'No HeadMakeReady price.<br/>';
				} else {
					$HeadMakeReady{Total} = $HeadMakeReady{Price} * $$specs{SetsOfNumbers} * $I->imposition();
					$Breakdown .= sprintf('HeadMakeReady Price: $%1$.2f%2$s * %4$d sets = $%3$.2f<br/>', @HeadMakeReady{'Price','units','Total'}, $$specs{SetsOfNumbers},  );
					$total += $HeadMakeReady{Total};
				} # end if

				my %ServicePrice;
				if ( $runs ) {
					%ServicePrice = openprint::service::get_price_object('Numbering'.$$specs{colour},$heads, $Equipment ); 
					%ServicePrice = openprint::service::get_price_object('Numbering',$heads, $Equipment ) if ! %ServicePrice;

					if ( ! %ServicePrice ) {
						$Breakdown .= 'No Service price.<br/>';
					} elsif ( $ServicePrice{units} eq 'per m' ) {
						$ServicePrice{Total} += $ServicePrice{Price} * $runs * $qty / 1000;
						$total += $ServicePrice{Total};
						$mprice += $ServicePrice{Price} * $runs / $I->imposition();
						$Breakdown .= sprintf('Service Price: %4$d runs of %5$d numbers : $%1$.4f%2$s = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $runs, $heads );
					} elsif ( sets::isin( $ServicePrice{units},[ 'per impression', 'each' ] ) ) {
						$ServicePrice{Total} += $ServicePrice{Price} * $runs * $qty;
						$total += $ServicePrice{Total};
						$mprice += $ServicePrice{Price} * $runs / $I->imposition();
						$Breakdown .= sprintf('Service Price: %4$d runs of %5$d numbers : $%1$.4f%2$s = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $runs, $heads );
					} # end if
				} # end if

				my %LastServicePrice;
				if ( $last_run ) {
					%LastServicePrice = openprint::service::get_price_object('Numbering'.$$specs{colour},$last_run, $Equipment );
					%LastServicePrice = openprint::service::get_price_object('Numbering',$last_run, $Equipment ) if ! %LastServicePrice;
					if ( ! %LastServicePrice ) {
						$Breakdown .= 'No Service price.<br/>';
					} elsif ( sets::isin( $LastServicePrice{units},[ 'per m' ] ) ) {
						$LastServicePrice{Total} += $LastServicePrice{Price} * $qty / 1000;
						$Breakdown .= sprintf('Service Price: 1 run of %4$d numbers : $%1$.4f%2$s = $%3$.2f<br/>', @LastServicePrice{'Price','units','Total'}, $last_run );
						$total += $LastServicePrice{Total};
						$mprice += $LastServicePrice{Price} / $I->imposition();
					} elsif ( sets::isin( $LastServicePrice{units},[ 'per impression', 'each' ] ) ) {
						$LastServicePrice{Total} += $LastServicePrice{Price} * $qty;
						$total += $LastServicePrice{Total};
						$mprice += $LastServicePrice{Price} / $I->imposition();
						$Breakdown .= sprintf('Service Price: 1 run of %4$d numbers : $%1$.4f%2$s = $%3$.2f<br/>', @LastServicePrice{'Price','units','Total'}, $last_run );
					} # end if
				} # end if
				
				$ImpPrice{Breakdown} = $Breakdown;
				$ImpPrice{total} = $total;
				$ImpPrice{mprice} = $mprice;
				$ImpPrice{ServicePrice} = \%ServicePrice;
				$ImpPrice{LastServicePrice} = \%LastServicePrice;
				$SetPrice{total} += $total;
				$SetPrice{mprice} += $mprice;
				$SetPrice{Breakdown} .= $Breakdown;
				push @{$SetPrice{Prices}}, \%ImpPrice;

			} # end foreach Imposition

			last if ! $complete;

			if ( my $minimumcharge = openprint::service::get_price('NumberingMinimumCharge', undef, $Equipment ) ) {
				$SetPrice{total} = $minimumcharge if $SetPrice{total} < $minimumcharge;
			} # end if

			$SetPrice{Breakdown} .= sprintf('Total: $%.2f<br/>', $SetPrice{total} );

			if ( ( ! defined $Results{Total} ) or $SetPrice{total} < $Results{Total} ) {
				$Results{Total} = $SetPrice{total};
				$Results{MPrice} = $SetPrice{mprice};
				$Results{Equipment} = $Equipment;
				$Results{Impositions} = $Impositions;
				$Results{Prices} = $SetPrice{Prices};
				$Results{SetPrice} = \%SetPrice;
			} # end if
		} # end foreach set of Impositions
		$Results{Breakdown} .= $Results{SetPrice}->{Breakdown}.'</fieldset>';
	} # end foreach Equipment

	if ( ! defined $Results{Total} ) {
		$Results{Status} = 'uncalculated';
	} else {
		$Results{Equipment} = $Results{Equipment};
	} # end if

	return \%Results;
} # end sub signature_calc

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	if ( $qty_index ) {
		return '';
	} # end if

	return sprintf( '%d set%s of %s numbers', $$specs{SetsOfNumbers}, ( $$specs{SetsOfNumbers} == 1 ? '' : 's' ), $$specs{colour} );
} # end sub summary

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;
} # end sub display

sub save {
} # end sub save

1;
__END__
