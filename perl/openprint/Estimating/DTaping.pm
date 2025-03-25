package openprint::Estimating::DTaping;
use strict;

require openprint::service;

use constant DEBUG => 0;

use vars qw( %ServicePrices %Specifications);
%ServicePrices = (
  DTapingMinimumCharge => {},
  DTapingMakeReady => {},
  DTaping => { units=> ['per inch', 'per m']},
);
%Specifications = (
  'DTapes Per Run' => {},
  'DTaping Capable' => { value=>['Y','N'] },
);

sub ServicePriceConfiguration {
  my $name = shift;
  $openprint::log->debug("Finding for $name");
  $openprint::log->debug( Data::Dumper::Dumper(\%ServicePrices));
  return $ServicePrices{$name} if $ServicePrices{$name};
  foreach my $key (keys %ServicePrices) {
    $openprint::log->debug("Trying $name =~ $key/");
    return $ServicePrices{$key} if ($name =~ /$key/i);
  }
  $openprint::log->debug("Not found for ($name)");
  return undef;
}
sub SpecificationConfiguration {
  return $Specifications{shift};
}

my %variables = (
	'ddmEquipment1' => ['save','output'], 'ddmEquipment2' => ['save','output'], 'ddmEquipment3' => ['save','output'],
	'OverridePrice1' => ['save'], 'OverridePrice2' => ['save'], 'OverridePrice3' => ['save'],
	'txtPrice1' => ['save','output'], 'txtPrice2' => ['save','output'], 'txtPrice3' => ['save','output'],
	'Markup1'	=> ['save'], 'Markup2'	=> ['save'], 'Markup3'	=> ['save'],
	'txtQuantity1' => ['save'], 'txtQuantity2' => ['save'], 'txtQuantity3' => ['save'],
);
sub variables {
	my ( $p_id, $s_id, $old_specs, $specs ) = @_;

    my @v;
    foreach my $k ( keys %variables ) {
        push @v, $k if sets::isin( 'save', $variables{$k} );
    } # end foreach;
	my $Project = new openprint::Project( $p_id );
	foreach my $s_s_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $s_s_id );
		push @v, "top-strips-$$sig_specs{SignatureIndex}";
		push @v, "bottom-strips-$$sig_specs{SignatureIndex}";
		push @v, "left-strips-$$sig_specs{SignatureIndex}";
		push @v, "right-strips-$$sig_specs{SignatureIndex}";
	} # end foreach signature
    return @v;
}

sub no_outputs {
    my @v;
    foreach my $k ( keys %variables ) {
        push @v, $k if ! sets::isin( 'output', $variables{$k} );
    } # end foreach;
    return @v;
}


sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $specs) = @_;

	my $Project = new openprint::Project( $pid );

	my @Equipment = openprint::Equipment->find('Specifications'=>{'DTaping Capable'=>'Y'},'useinestimating'=>1);
	if ( ! @Equipment ) {
		$$specs{'alert'} = 'We have no dtaping equipment.';
		return $$specs{'Status'} = 'uncalculated';
	} # end if

	foreach my $ss_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );
		foreach my $side ( 'top','bottom','left','right' ) {
			if ( $$specs{"$side-strips-$$sig_specs{SignatureIndex}"} eq '' ) {
				$$specs{'alert'} .= "Please select the # of DTapes on the $side";
				if ( $Project->signatures() > 1 ) {
					$$specs{'alert'} .= ' of signature '.$$sig_specs{'SignatureIndex'};
				} else {
					$$specs{'alert'} .= '.';
				} # end if
				return $$specs{'Status'} = 'uncalculated';
			} # end if
		} # end foreach side
	} # end foreach

	my $status = 'calculated';

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{'txtPrice'.$qty_index} =~ s/[^\d\.]//g;
		$$specs{'Markup'.$qty_index} =~ s/[^\d\.\-]//g;
		$$specs{'txtQuantity'.$qty_index} =~ s/[^\d\.]//g;
		$$specs{'txtQuantity'.$qty_index} = $Project->quantity( $qty_index ) if ! $$specs{'txtQuantity'.$qty_index};
		next if ! $$specs{'txtQuantity'.$qty_index};

		my %BestPrice;
		$$specs{'hdnBreakdown'.$qty_index} = '';

		foreach my $Equipment ( @Equipment ) {
			$$specs{'hdnBreakdown'.$qty_index} .= '<fieldset><legend>'.$Equipment->name().'</legend>';
			my $dtapes_per_run = $Equipment->specification('DTapes Per Run');
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Dtapes per run: %d<br/>',$dtapes_per_run) if $dtapes_per_run;

			my $total = 0;

			my %MakeReady = openprint::service::get_price_object('DTapingMakeReady', undef, $Equipment );
			if ( ! %MakeReady ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No MakeReady price.<br/>';
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('MakeReady Price: $%1$.2f%2$s<br/>', @MakeReady{'Price','units'} );
				$total += $MakeReady{'Price'};
			} # end if

			foreach my $ss_id ( $Project->signatures() ) {
				my $sig_specs = openprint::service::get_specs_ref( $Project, $ss_id );

				my $length;
				foreach my $side ( 'top','bottom' ) {
					if ( $$specs{"$side-strips-$$sig_specs{SignatureIndex}"} ) {
						$length += $$sig_specs{'txtFinalWidth'} * $$specs{"$side-strips-$$sig_specs{SignatureIndex}"};
					} # end if
				} # end foreach
				foreach my $side ( 'left','right' ) {
					if ( $$specs{"$side-strips-$$sig_specs{SignatureIndex}"} ) {
						$length += $$sig_specs{'txtFinalHeight'} * $$specs{"$side-strips-$$sig_specs{SignatureIndex}"};
					} # end if
				} # end foreach

				foreach my $side ( 'top','bottom','left','right' ) {
					my $runs = $dtapes_per_run ? int($$specs{"$side-strips-$$sig_specs{SignatureIndex}"} / $dtapes_per_run) : 0;
					my $last_run = $dtapes_per_run ? ($$specs{"$side-strips-$$sig_specs{SignatureIndex}"} - ( $dtapes_per_run * $runs) ) % $dtapes_per_run : $$specs{"$side-strips-$$sig_specs{SignatureIndex}"};

					if ( $runs ) {
						my %ServicePrice = openprint::service::get_price_object('DTaping',$dtapes_per_run ? $dtapes_per_run : undef, $Equipment ); 
						if ( ! %ServicePrice ) {
							$$specs{'hdnBreakdown'.$qty_index} .= "$side : No Service price for $dtapes_per_run tapes on $$Equipment{name}.<br/>";
						} else {
							if ( sets::isin( lc $ServicePrice{'units'},[ 'per 1000', 'per m' ] ) ) {
								$ServicePrice{'Total'} += $ServicePrice{'Price'} * $runs * $$specs{'txtQuantity'.$qty_index} / 1000;
							} elsif ( lc $ServicePrice{'units'} eq 'per inch' ) {
								$ServicePrice{'Total'} += $ServicePrice{'Price'} * $length * $$specs{'txtQuantity'.$qty_index};
							} # end if
							$total += $ServicePrice{'Total'};
							$$specs{'hdnBreakdown'.$qty_index} .= sprintf('%6$s Service Price: %4$d runs of %5$d tapes : $%1$.2f%2$s = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $runs, $dtapes_per_run, $side );
						} # end if
					} # end if

					if ( $last_run ) {
						my %LastServicePrice;
						%LastServicePrice = openprint::service::get_price_object('DTaping', $last_run, $Equipment );
						if ( ! %LastServicePrice ) {
							$$specs{'hdnBreakdown'.$qty_index} .= 'No Service price.<br/>';
						} else {
							if ( sets::isin( lc $LastServicePrice{'units'},[ 'per 1000', 'per m' ] ) ) {
								$LastServicePrice{'Total'} += $LastServicePrice{'Price'} * $$specs{'txtQuantity'.$qty_index} / 1000;
							} elsif ( lc $LastServicePrice{'units'} eq 'per inch' ) {
								$LastServicePrice{'Total'} += $LastServicePrice{'Price'} * $length * $$specs{'txtQuantity'.$qty_index};
							} # end if
							$$specs{'hdnBreakdown'.$qty_index} .= sprintf('%5$s Service Price: 1 run of %4$d tapes : $%1$.2f%2$s = $%3$.2f<br/>', @LastServicePrice{'Price','units','Total'}, $last_run, $side );
							$total += $LastServicePrice{'Total'};
						} # end if
					} # end if
				} # end foreach side

				# Calculate Material costs
				my $Material = openprint::Material->find_one('name'=>'DTape');
				if ( $Material ) {
					my %MaterialPrice = $Material->get_price( $length );
					if ( lc $MaterialPrice{'units'} eq 'per inch' ) {
						$MaterialPrice{'Total'} = $MaterialPrice{'Price'} * $length * $$specs{'txtQuantity'.$qty_index};
					} # end if
					$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Material Price: %4$.1finches of DTape : $%1$.2f%2$s = $%3$.2f<br/>', @MaterialPrice{'Price','units','Total'}, $length );
					$total += $MaterialPrice{'Total'};
				} # end if Material
			} # end foreach signature
			
			if ( my $minimumcharge = openprint::service::get_price('DTapingMinimumCharge', undef, $Equipment ) ) {
				$total = $minimumcharge if $total < $minimumcharge;
			} # end if
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Total: $%.2f<br/>', $total );
			
			if ( ( ! defined $BestPrice{'Total'} ) or $total < $BestPrice{'Total'} ) {
				$BestPrice{'Total'} = $total;
				$BestPrice{'Equipment'} = $Equipment;
			} # end if
			$$specs{'hdnBreakdown'.$qty_index} .= '</fieldset>';
        } # end foreach Equipment

		if ( ! defined $BestPrice{'Total'} ) {
			$status = 'uncalculated';
		} else {
			$$specs{'ddmEquipment'.$qty_index} = $BestPrice{'Equipment'}->id();
		} # end if

		if ( $$specs{'OverridePrice'.$qty_index} ne 'Y' ) {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{'ProjectMoneyFormat'}, 
$BestPrice{'Total'}*(1+$$specs{"Markup$qty_index"}/100) * (1+$Project->markup()/100) );
		} else {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{'ProjectMoneyFormat'}, $$specs{'txtPrice'.$qty_index} );
		} # end if
		$$specs{'txtUnitPrice'.$qty_index} = sprintf($openprint::config{'UnitPriceFormat'}, 
				( $BestPrice{'Total'}/ $$specs{'txtQuantity'.$qty_index} ) * (1+$Project->markup()/100) );

    } # end foreach qty_index
    return $$specs{'Status'} = $status;
} # end sub calc

sub summary {
	my ( $Project, $service_id, $specs, $qty_index ) = @_;

	$specs = openprint::service::get_specs_ref( $Project, $service_id ) if ! $specs;
	if ( $qty_index ) {
		if ( $$specs{'ddmEquipment'.$qty_index} ) {
			my $Equipment = new openprint::Equipment( $$specs{'ddmEquipment'.$qty_index} );
			return ' on ' . $Equipment->name();
		} # end if
		return '';
	} # end if

	my @sigs = $Project->signatures();

	if ( 1 == @sigs ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project, $sigs[0] );
		my $text = '';

		foreach my $side ( 'top','bottom','left','right' ) {
		$text .= $$specs{"$side-strips-$$sig_specs{'SignatureIndex'}"}." on the $side\n" if $$specs{"$side-strips-$$sig_specs{SignatureIndex}"};
		} # end foreach
		return $text;
	} # end if

	return '';
} # end sub summary

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	my @possible_equipment = openprint::Equipment->find( 'Specifications' => {'DTaping Capable'=>'Y'}, 'useinestimating'=>1,'order'=>'lower(strName)');
	@{$$variable{'Equipment'}} = @possible_equipment;
} # end sub display

sub save {
} # end sub save
1;
__END__
