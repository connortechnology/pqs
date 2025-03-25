package openprint::Estimating::Tipping;
use strict;

require openprint::service;
use POSIX           qw(ceil);
use vars qw( %ServicePrices );

use constant DEBUG => 0;

my %variables = (
	'Quantity' => ['save'],
	'chkOverrideEquipment1'	=> ['save'], 'chkOverrideEquipment2'	=> ['save'], 'chkOverrideEquipment3'	=> ['save'],
	'ddmEquipment1' => ['save','output'], 'ddmEquipment2' => ['save','output'], 'ddmEquipment3' => ['save','output'],
	'OverridePrice1' => ['save'], 'OverridePrice2' => ['save'], 'OverridePrice3' => ['save'],
	'txtPrice1' => ['save','output'], 'txtPrice2' => ['save','output'], 'txtPrice3' => ['save','output'],
	'MPrice1' => ['save','output'], 'MPrice2' => ['save','output'], 'MPrice3' => ['save','output'],
	'Markup1'	=> ['save'], 'Markup2'	=> ['save'], 'Markup3'	=> ['save'],
	'txtQuantity1' => ['save'], 'txtQuantity2' => ['save'], 'txtQuantity3' => ['save'],
);
sub variables {
    my @v;
    foreach my $k ( keys %variables ) {
        push @v, $k if sets::isin( 'save', $variables{$k} );
    } # end foreach;
    return @v;
}

sub no_outputs {
    my @v;
    foreach my $k ( keys %variables ) {
        push @v, $k if ! sets::isin( 'output', $variables{$k} );
    } # end foreach;
    return @v;
}

sub neccessary {
	my ( $Project ) = @_;

	my $services = $Project->services( );
	if ( $$services{''} ) {
		my $project_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] );
		return 1 if $$project_specs{TippingQuantity};
	} # end if
	return 0;
} # end sub neccessary

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $specs) = @_;

	my $Project = new openprint::Project( $pid );
	my $services = $Project->services();
	my $project_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] ) if $$services{''};
	my @signatures = $Project->signatures();
	my $sig_specs = openprint::service::get_specs_ref( $Project, $signatures[0] );
	my $folding_specs;

	my @capable = ('Y');
	if ( $$services{SaddleStitching} or $$services{LoopStitching} ) {
		push @capable, 'When Stitching';
	} elsif ( $$services{PerfectBind} ) {
		push @capable, 'When PerfectBound';
	} elsif ( $$services{Folding} ) {
		push @capable, 'When Folding';
		$folding_specs = openprint::service::get_specs_ref( $Project, $$services{Folding}[0] );
	} # end if

	if ( ! $$specs{Quantity} ) {
		$$specs{Quantity} = $$project_specs{TippingQuantity};
	} # end if
	$$specs{Quantity} =~ s/\D//g;
	if ( ! $$specs{Quantity} ) {
		$$specs{alert} = 'Please enter the number of tip-ins.';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my @Equipment = openprint::Equipment->find( Specifications=>{'Tipping Capable'=>\@capable}, useinestimating=>1);
	if ( ! @Equipment ) {
		$$specs{alert} = 'We have no equipment for tip-ins.';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my $status = 'calculated';

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{'Markup'.$qty_index} =~ s/[^\d\.\-]//g;
		$$specs{'txtPrice'.$qty_index} =~ s/[^\d\.]//g;
		$$specs{'txtQuantity'.$qty_index} =~ s/[^\d\.]//g;
		$$specs{'txtQuantity'.$qty_index} = $Project->quantity( $qty_index ) if ! $$specs{'txtQuantity'.$qty_index};

		my %BestPrice;
		$$specs{'hdnBreakdown'.$qty_index} = '';

		my @my_equipment;
		if ( $$specs{'chkOverrideEquipment'.$qty_index} eq 'Y' ) {
			@my_equipment = ( new openprint::Equipment( $$specs{'ddmEquipment'.$qty_index} ) );
		} else {
			@my_equipment = @Equipment;
		} # end if

		foreach my $Equipment ( @my_equipment ) {
			$$specs{'hdnBreakdown'.$qty_index} .= '<fieldset><legend>'.$Equipment->name().'</legend>';
			if ( $Equipment->specification('Tipping Capable') eq 'When Folding' ) {
				if ( $Equipment->id() != $$folding_specs{"ddmEquipment-$$sig_specs{SignatureIndex}-$qty_index"} ) {
					$$specs{'hdnBreakdown'.$qty_index} .= 'Not folding on ' . $Equipment->name() . '. Folding on '.new openprint::Equipment($$folding_specs{"ddmEquipment-$$sig_specs{SignatureIndex}-$qty_index"})->name().'<br/>';
					next;
				} # end if
			} elsif ( $_ = $Equipment->specification('Tipping Maximum Quantity') and $_ < $$specs{'txtQuantity'.$qty_index} ) {
				$$specs{'hdnBreakdown'.$qty_index} .= "Has Maximum Quantity and $_ < " . $$specs{'txtQuantity'.$qty_index}.'<br/>';
				next;
			} elsif ( $_ = $Equipment->specification('Tipping Minimum Quantity') and $_ > $$specs{'txtQuantity'.$qty_index} ) {
				$$specs{'hdnBreakdown'.$qty_index} .= "Has Minimum Quantity and $_ > " . $$specs{'txtQuantity'.$qty_index}.'<br/>';
				next;
			} # end if
			my $max_tip_ins = $Equipment->specification('Maximum Tip-ins');
			if ( $max_tip_ins and ( $max_tip_ins < $$specs{Quantity} ) ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'Maximum tip-ins: ' . $max_tip_ins.'<br/>';
				next;
			} # end if

			my $total = 0;

			my %MakeReady = openprint::service::get_price_object('TippingMakeReady', undef, $Equipment );
			if ( ! %MakeReady ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No MakeReady price.<br/>';
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('MakeReady Price: $%1$.2f%2$s<br/>', @MakeReady{'Price','units'} );
				$total += $MakeReady{Price};
			} # end if

			my %ServicePrice = openprint::service::get_price_object('Tipping', undef, $Equipment ); 
			if ( ! %ServicePrice ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No Service price.<br/>';
			} elsif ( lc $ServicePrice{units} eq 'per m' ) {
				$ServicePrice{Total} += $ServicePrice{Price} * $$specs{'txtQuantity'.$qty_index} / 1000;
				$total += $ServicePrice{Total};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service Price: $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $$specs{'txtQuantity'.$qty_index} );
			} elsif ( lc $ServicePrice{units} eq 'each' ) {
				$ServicePrice{Total} += $ServicePrice{Price} * $$specs{'txtQuantity'.$qty_index};
				$total += $ServicePrice{Total};
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Service Price: $%1$.2f%2$s * %4$d = $%3$.2f<br/>', @ServicePrice{'Price','units','Total'}, $$specs{'txtQuantity'.$qty_index} );
			} # end if

			if ( my $minimumcharge = openprint::service::get_price('TippingMinimumCharge', undef, $Equipment ) ) {
				$total = $minimumcharge if $total < $minimumcharge;
			} # end if
			$$specs{'hdnBreakdown'.$qty_index} .= sprintf('Total: $%.2f<br/>', $total );
			
			if ( ( ! defined $BestPrice{Total} ) or $total < $BestPrice{Total} ) {
				$BestPrice{Total} = $total;
				$BestPrice{Equipment} = $Equipment;
				$BestPrice{ServicePrice} = \%ServicePrice;
			} # end if
			$$specs{'hdnBreakdown'.$qty_index} .= '</fieldset>';
        } # end foreach Equipment

		if ( ! defined $BestPrice{Total} ) {
			$status = 'uncalculated';
		} else {
			$$specs{'ddmEquipment'.$qty_index} = $BestPrice{Equipment}->id();
		} # end if

		my $unitPrice = $BestPrice{ServicePrice}{Total} / $$specs{'txtQuantity'.$qty_index};
		if ( $Project->markup() ) {
			my $markup = (1+$Project->markup()/100);;
			$unitPrice *= $markup;
			$BestPrice{Total} *= $markup;
		}

		$$specs{'txtUnitPrice'.$qty_index} = sprintf($openprint::config{UnitPriceFormat}, 
			$openprint::config{UnitPriceRounding} ? Math::Round::nearest( $openprint::config{UnitPriceRounding}, $unitPrice ) : $unitPrice );
		$$specs{'MPrice'.$qty_index} = sprintf($openprint::config{UnitPriceFormat}, (1+$$specs{"Markup$qty_index"}/100) * (($BestPrice{ServicePrice}{Total} / $$specs{'txtQuantity'.$qty_index})*1000) * (1+$Project->markup()/100) );
		if ( $$specs{'OverridePrice'.$qty_index} ne 'Y' ) {
			if ( $$specs{"Markup$qty_index"} ) {
				$BestPrice{Total} *= (1+$$specs{"Markup$qty_index"}/100);
			}
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{ProjectMoneyFormat}, 
					$openprint::config{ProjectPriceRounding} ? Math::Round::nearest( $openprint::config{ProjectPriceRounding}, $BestPrice{Total} ) : $BestPrice{Total}
					);

		} else {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{ProjectMoneyFormat}, $$specs{'txtPrice'.$qty_index} );
		} # end if

    } # end foreach qty_index
    return $status;
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

	return sprintf( '%d tip in%s', $$specs{Quantity}, $$specs{Quantity} == 1 ? '' : 's' );
} # end sub summary

sub save {
	my ( $p_id, $s_id, $param ) = @_;
	my $Project = new openprint::Project( $p_id );
	my $services = $Project->services();
	openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $p_id, $$services{''}[0], 'TippingQuantity', $$param{Quantity} );
	
} # end sub save

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
	my @capable = ('Y');
	if ( $$services{SaddleStitching} or $$services{LoopStitching} ) {
		push @capable, 'When Stitching';
	} elsif ( $$services{PerfectBind} ) {
		push @capable, 'When PerfectBound';
	} elsif ( $$services{Folding} ) {
		push @capable, 'When Folding';
	} # end if
	my @possible_equipment = openprint::Equipment->find( Specifications => {'Tipping Capable'=>\@capable}, useinestimating=>1, order=>'lower(strName)');
	$$variable{Equipment} = \@possible_equipment;
} # end sub display

1;
__END__
