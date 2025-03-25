package openprint::Estimating::Blowing;
use strict;
use vars qw( %ServicePrices %MaterialPrices );
%ServicePrices = (
	'BlowingMakeReady'	=> { },
	'Blowing'			=> { units => [ 'per m', 'each' ], },
	'BlowingMinimumCharge'	=> { },
);

require openprint::service;

use constant DEBUG => 0;

my %variables = (
	'alert' => ['save','output'],
	'Quantity' => ['save'],
	'ddmEquipment1' => ['save','output'], 'ddmEquipment2' => ['save','output'], 'ddmEquipment3' => ['save','output'],
	'OverridePrice1' => ['save'], 'OverridePrice2' => ['save'], 'OverridePrice3' => ['save'],
	'Markup1'=>['save'], 'Markup2'=>['save'], 'Markup3'=>['save'],
	'txtPrice1' => ['save','output'], 'txtPrice2' => ['save','output'], 'txtPrice3' => ['save','output'],
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
		return 1 if $$project_specs{BlowingQuantity};
	} # end if
	return 0;
} # end sub neccessary

sub calc {
    my ($log, $dbh, $variable, $pid, $sid, $specs) = @_;

	my $Project = new openprint::Project( $pid );
	my $services = $Project->services();
	my $project_specs = openprint::service::get_specs_ref( $Project, $$services{''}[0] ) if $$services{''};

	if ( ! $$specs{Quantity} ) {
		$$specs{Quantity} = $$project_specs{BlowingQuantity};
	} # end if
	$$specs{Quantity} =~ s/\D//g;
	if ( ! $$specs{Quantity} ) {
		$$specs{alert} = 'Please enter the number of blow-ins.';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my @capabilities = ( 'Y', 
			( $$services{PerfectBind} ? ( 'When PerfectBound' ) : () ),
			( $$services{SaddleStitching} or $$services{LoopStitching} ? ( 'When Stitching' ) : () ),
			);
	
	my @Equipment = openprint::Equipment->find('Specifications'=>{'Blowing Capable'=>\@capabilities},'useinestimating'=>1);
	if ( ! @Equipment ) {
		$$specs{alert} = 'We have no equipment for blow-ins.';
		return $$specs{Status} = 'uncalculated';
	} # end if

	my $status = 'calculated';

	my $BlowingMakeReady = openprint::Service->find_one(name=>'BlowingMakeReady');
	my $Blowing = openprint::Service->find_one(name=>'Blowing');

	foreach my $qty_index ( $Project->quantity_indexes() ) {
		$$specs{'txtPrice'.$qty_index} =~ s/[^\d\.]//g;
		$$specs{'Markup'.$qty_index} =~ s/[^\-\d\.]//g;
		$$specs{'txtQuantity'.$qty_index} =~ s/[^\d\.]//g;
		$$specs{'txtQuantity'.$qty_index} = $Project->quantity( $qty_index ) if ! $$specs{'txtQuantity'.$qty_index};
		next if ! $$specs{'txtQuantity'.$qty_index};

		my %BestPrice;
		$$specs{'hdnBreakdown'.$qty_index} = '';

		foreach my $Equipment ( @Equipment ) {
			$$specs{'hdnBreakdown'.$qty_index} .= '<fieldset><legend>'.$Equipment->name().'</legend>';
			my $max_blow_ins = $Equipment->specification('Maximum Blow-ins');
			if ( $max_blow_ins and ( $max_blow_ins < $$specs{Quantity} ) ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'Maximum blow-ins: ' . $max_blow_ins.'<br/>';
				next;
			} # end if

			my $total = 0;

			my %MakeReady = $BlowingMakeReady->get_price( undef, $Equipment ) if $BlowingMakeReady;
			if ( ! %MakeReady ) {
				$$specs{'hdnBreakdown'.$qty_index} .= 'No MakeReady price.<br/>';
			} else {
				$$specs{'hdnBreakdown'.$qty_index} .= sprintf('MakeReady Price: $%1$.2f%2$s<br/>', @MakeReady{'Price','units'} );
				$total += $MakeReady{Price};
			} # end if

			my %ServicePrice = $Blowing->get_price( undef, $Equipment ) if $Blowing;
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

			if ( my $minimumcharge = openprint::service::get_price('BlowingMinimumCharge', undef, $Equipment ) ) {
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

		$$specs{'txtUnitPrice'.$qty_index} = sprintf($openprint::config{UnitPriceFormat}, ( $BestPrice{ServicePrice}{Total} / $$specs{'txtQuantity'.$qty_index} ) * (1+$Project->markup()/100) );
		if ( $$specs{'OverridePrice'.$qty_index} ne 'Y' ) {
			$$specs{'txtPrice'.$qty_index} = sprintf( $openprint::config{ProjectMoneyFormat}, $BestPrice{Total} * (1+$$specs{"Markup$qty_index"}/100) * (1+$Project->markup()/100) );
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

	return sprintf( '%d blow in%s', $$specs{Quantity}, $$specs{Quantity} == 1 ? '' : 's' );
} # end sub summary

sub save {
	my ( $p_id, $s_id, $param ) = @_;
	my $Project = new openprint::Project( $p_id );
	my $services = $Project->services();
	openprint::service::insert_service_spec( $openprint::log, $openprint::dbh, $p_id, $$services{''}[0], 'BlowingQuantity', $$param{Quantity} );
	
} # end sub save

sub display {
	my ( $log, $dbh, $variable, $project_index, $service_index ) = @_;

	my $Project = new openprint::Project( $project_index );
	my $services = $Project->services();
	my @capabilities = ( 'Y', 
			( $$services{PerfectBind} ? ( 'When PerfectBound' ) : () ),
			( $$services{SaddleStitching} or $$services{LoopStitching} ? ( 'When Stitching' ) : () ),
			);
	
	$$variable{Equipment} = [ openprint::Equipment->find('Specifications'=>{'Blowing Capable'=>\@capabilities},'useinestimating'=>1, order=>'lower(strName)') ];
} # end sub display

1;
__END__
