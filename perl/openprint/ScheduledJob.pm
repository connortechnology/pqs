use strict;
package openprint::ScheduledJob;
our @ISA = qw(openprint::Object);
require openprint::Object;

use openprint ();
use vars qw(%variable $log $dbh %session $debug $table $serial %fields %find_fields %transforms %defaults );
*variable = \%openprint::variable;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*session = \%openprint::session;

require sql;
require ssi;
require misc;
require Date::Parse;
require openprint::User;
require openprint::PaperAllocation;
require openprint::Shift;
require openprint::employee_production;
require openprint::ProductionFeedback;

my $parser = 'DateTime::Format::Pg';

$debug = 0;
$table = 'schedule';
$serial = 'schedule_id_seq';

%fields = (
	id							=>	'id',
	starttime				=>	'starttime',
	runtime					=>	'runtime',
	project_id			=>	'projectindex',
	service_id			=>	'service_id',
	pertains_id			=>	'pertains_id',
	equipment_id		=>	'equipment_id',
	locked					=>	'starttime_locked',
	speed						=>	'speed',
	comment					=>	'comment',
	runtime_seconds	=>	undef,
	starttime_seconds	=>	undef,
	impressions		=>	'impressions',
	created_on		=>	'created_on',
	operator_id		=>	undef,
	stock_verified	=>	'stock_verified',
	stock			=>	'stock',
	servicetype_id	=>	'servicetype_id',
	tentative		=>	'tentative',
);

%find_fields = (
	servicetype		=>	'(SELECT name FROM service_types WHERE id=servicetype_id)',
);

%transforms = (
	id				=>	[ 's/\D//g' ],
	project_id		=>	[ 's/\D//g' ],
	speed			=>	[ 's/\D//g' ],
	#runtime		=>	[ 's/[^\d:]//g' ],
);

%defaults = (
	speed			=>	undef,
	created_on		=>	q`'NOW()'`,
	stock_verified	=>	0,
	tentative		=>	0,
);

sub runtime_seconds {
	if ( @_ > 1 ) {
		$_[0]{runtime} = misc::seconds2hms($_[1]);
	} # end if

	my $seconds = $_[0]->runtime() ? misc::hms2time($_[0]->runtime()) : 0;

	if ( ! $seconds ) {
		$log->error("Got nothing for $_[0]{runtime} from misc::hms2time :" . $_[0]->to_string());
	} elsif ( $debug ) {
		$log->debug("Got $seconds seconds for $_[0]{runtime} from misc::hms2time");
	}
	
	return $seconds;
} # end sub runtime_seconds

sub starttime {
	if ( @_ > 1 ) {
		$_[0]{starttime} = $_[1];
		delete $_[0]{Shift};
		$_[0]->endtime(undef);
	} # end if
	return $_[0]{starttime};
} # end sub starttime

sub starttime_seconds {
	my $starttime_dt;

	if ( @_ > 1 ) {
		if ( $_[1] < ( time - 10 ) ) {
			$starttime_dt = DateTime->from_epoch( epoch=>$_[1], time_zone=>$openprint::TZ );
			$log->error( 'ScheduledJob: startime_seconds < NOW() ' . $parser->format_datetime( $starttime_dt ) );
		} # end if
		$starttime_dt = DateTime->from_epoch( epoch=>$_[1], time_zone=>$openprint::TZ );
$openprint::log->debug("Setting starttime_seconds to $_[1] => $starttime_dt");
		$_[0]->starttime( $parser->format_datetime( $starttime_dt ) );
$openprint::log->debug("Got $starttime_dt = $_[0]{starttime}");
		
	} elsif ( $_[0]{starttime} ) {
		
		$starttime_dt = $parser->parse_datetime( $_[0]{starttime} );
	} # end if
	return $starttime_dt->epoch() if $starttime_dt;
	return;
} # endsub

sub startdate_seconds {
	my ( $self ) = @_;
	my $time = $self->starttime_seconds();
	return Date::Parse::str2time( Date::Format::time2str( '%Y-%m-%d', $time ) );
} # end sub startdate_seconds

sub endtime {
	if ( @_ > 1 ) {
		$_[0]{endtime} = $_[1];
	}
	if ( ! $_[0]{endtime} ) {
		if ( $_[0]{starttime} ) {
			# Can only have an endtime if we have a starttime
			$_[0]{endtime} = Date::Format::time2str( '%Y-%m-%d %H:%M:%S%z', $_[0]->starttime_seconds() + $_[0]->runtime_seconds() );
		}
	} # end if
	return $_[0]{endtime};
} # end sub endtime

sub endtime_seconds {
	return $_[0]->starttime_seconds() + $_[0]->runtime_seconds();
} # end sub endtime_seconds

sub Equipment {
	return new openprint::Equipment( $_[0]{equipment_id} );
} # end sub Equipment

sub comment {
	my ( $self, $comment ) = @_;

	# We check for comments in the services, if we find one, we use it, otherwise we generate from the first.
	if ( @_ > 1 ) {
		$$self{comment} = $comment;
	} # end if

	if ( ( ! $$self{comment} ) and $$self{project_id} and $$self{service_id} and @{$$self{service_id}} ) {
		my $Project = $self->Project();
		if ( ! $$Project{id} ) {
			$log->error("Job has project_id that no longer exists( $$self{project_id})");
		} # end if
		my $ServiceType = $self->ServiceType();

		if ( $ServiceType->name() eq 'Folding' ) {
			my $qty_index = $Project->ordered_quantity_index();
			if ( ! $qty_index ) {
				$log->error("No qty for project $$Project{id} docket: $$Project{docket}");
				$qty_index = 1;
			}

			foreach my $service_index ( @{$$self{service_id}} ) {
				my $Service = $Project->Service( $service_index );
				my $specs = $Service->specs();

				foreach my $sig_id ( @{$self->pertains_id()} ) {
					my $SignatureService = $Project->Service( $sig_id );
					if ( ! $$SignatureService{service_id} ) {
						$log->error("Signature service $sig_id not foudn in project $$Project{id}");
					} # end if
					my $sig_specs = $SignatureService->specs();

					my $Imposition = new openprint::Imposition();
					$Imposition->load( $sig_specs, $qty_index, $Project );
					my @Folds = openprint::Estimating::Folding::get_Folds( $specs, $Imposition, $Project->ordered_quantity_index() );
					foreach my $FI ( @Folds ) {
						$comment .= 'Form ' .$$sig_specs{SignatureIndex} . ': ' . $FI->quantity() . ' ' . $$FI{imposition} . 'out ' . $$FI{Fold}->type() . '<br/>';
					} # end foreach For
				} # end foreach sig_id
				$comment = 'unknown fold' if ! $comment;
			} # end foreach service_index

		} elsif ( $ServiceType->name() eq 'Cutting' ) {
		} elsif ( $ServiceType->name() eq 'SaddleStitching' ) {
			my $services = $Project->services();

			$comment .= openprint::Estimating::MultiPage::schedule_summary( $Project, openprint::service::get_specs_ref( $Project, $$services{''}[0] ), $Project->ordered_quantity_index() ).'<br/>';
			my $service_specs = openprint::service::get_specs_ref( $Project, $$self{service_id}[0] );
			$comment .= openprint::Estimating::Stitching::schedule_summary( $Project, $$self{service_id}[0], $service_specs, $Project->ordered_quantity_index() )
		} else {
			my $service_specs = openprint::service::get_specs_ref( $Project, $$self{service_id}[0] );
			$comment = openprint::Estimating::Printing::get_colour_description_no_coverage($Project, $service_specs);
			my $Equipment = $self->Equipment();

			if ( $Equipment->specification('Folding Capable') eq 'When Printing' ) {
				my $services = $Project->services();
				if ( $$services{Folding} ) {
					my $fold_specs = openprint::service::get_specs_ref( $Project, $$services{Folding}[0] );
					if ( $$fold_specs{'ddmEquipment-'.$$service_specs{SignatureIndex}.'-'.$Project->ordered_quantity_index()} == $Equipment->id() ) {
						my $Imposition = new openprint::Imposition();
						$Imposition->load( $service_specs, $Project->ordered_quantity_index(), $Project );
						my $foldtype = sprintf('%sx%s-%dPage-%sFold', @$Imposition{'spread_columns','spread_rows','pages'}, $openprint::Imposition::Orientations{$$Imposition{'image_orientation'}} );
						$comment .= "($foldtype inline)";
					} else {
						$comment .= '(sheeted)';
					} # end if
				} # end if
			} # end if
		} # end if
		return $comment;
	} # end if has service_ids

	return $$self{comment};
} # end sub comment

sub stock {
	my ( $self, $stock ) = @_;
	if ( @_ == 2 ) {
		$$self{stock} = $stock;
	} # end if
	if ( ( ! $$self{stock} ) and $$self{project_id} and ( $self->ServiceType()->name() eq 'Signature' ) ) {
		$$self{stock} = '<p>Stock: ';
		my $Equipment = $self->Equipment();
		my $Project = new openprint::Project( $$self{project_id} );
		my $Stock;
		my $PA = openprint::PaperAllocation->find_one( docket=>$Project->docket() );
		if ( $PA ) {
			$Stock = $PA->Paper();
		} elsif ( $$self{service_id}[0] ) {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $$self{service_id}[0] );
			$Stock = openprint::Paper::load_from_signature( $Project, $sig_specs, $Project->ordered_quantity_index() ) if ! $Stock;
		} # end if
		if ( $Equipment->smartscheduling() ) {
			if ( $Stock ) {
				$$self{stock} .= join(' ', ( $Stock->brand(), $Stock->finish(), $Stock->colour(), $Stock->weight(), $Stock->type() eq 'Roll' ? $Stock->width.'&quot; Roll' : $Stock->width().'x'.$Stock->height() ) );
				$$self{stock} .= ' FSC:' . $$Stock{fsc_code} if $$Stock{fsc_code};
			} else {
				$$self{stock} .= ' not allocated.';
			} # end if
			if ( ( ! $PA ) and $Project->docket() and ( my @PO = openprint::PurchaseOrder_Content->find(docket=>$Project->docket()) ) ) {
				$$self{stock} .= ' Ordered on PO: ' . join(',', map { sprintf('<a href="/employee/purchase_order/view.html?po_id=%1$d">%1$d</a>' , $_->po_id() ); } @PO );
			} else {
				$$self{stock} .= ' not ordered.';
			} # end if
		} elsif ( $Stock ) {
			if ( $Stock->type() eq 'Roll' ) {
				$$self{stock} .= $Stock->width().'&quot; Roll';
			} else {
				$$self{stock} .= $Stock->width() . 'x' . $Stock->height();
			} # end if
		} # end if
		$$self{stock} .= '</p>';
	} # end if
	return $$self{stock};
} # end sub stock

my %printing_service_type_ids;
my %bindery_service_type_ids;

sub get_li {
	my ( $self, $ul_id ) = @_;

# a 12hour shift ~= 600px, so each hour gets 50px;
	my $scale = $session{'/employee/production/print_overview.html?scale'};
	my @Presses = split(';', $session{'/employee/production/print_overview.html?Presses'} );
	my $min_height = 50 + ( 10 * ( @Presses ? @Presses : 1 ) );
	my $height;
	if ( ! $scale ) {
		#$height = $min_height;
	} else {
		$height = $self->starttime() ? $scale * int($self->runtime_seconds()/3600) : $min_height;
		$height = $min_height if $height < $min_height;
	} # end if

	my $html;

	my $Project = $self->Project();
	my $services = $Project->services();
	my $Equipment = $self->Equipment();

	my $colour = '';
	%printing_service_type_ids = map { $$_{id}, $$_{id} } openprint::ServiceType->find(category=>'Printing') if ! %printing_service_type_ids;
	%bindery_service_type_ids = map { $$_{id}, $$_{id} } openprint::ServiceType->find(category=>'Bindery') if ! %bindery_service_type_ids;
	my %status_colours = (
			'In Prepress' => 'inprepress',
			'Proofs Out' => 'inprepress',
			'Waiting For QA Approval' => 'inprepress',
			'Printed' => 'complete',
			'Complete' => 'complete',
			'Waiting for Pickup' => 'complete',
			'Picked Up' => 'complete',
			'Shipped' => 'complete',
			'Waiting For Customer Approval' => 'approval',
			);

	my @equipment;

	if ( $$self{project_id} ) {
		$colour .= $status_colours{$$Project{status}};

		if ( $printing_service_type_ids{$$self{servicetype_id}} ) {
			@equipment = sets::union( map { $_->equipment_id() ? $_->equipment_id() : () } openprint::ScheduledJob->find( project_id=>$$self{project_id}, servicetype_id=>[ keys %printing_service_type_ids ] ) );
			if ( sets::exclude( [ $$self{equipment_id} ], \@equipment ) ) {
				$colour .= ' multipress';
			}
		} elsif ( $bindery_service_type_ids{$$self{servicetype_id}} ) {
			@equipment = sets::union( map { $_->equipment_id() ? $_->equipment_id() : () } openprint::ScheduledJob->find( project_id=>$$self{project_id}, servicetype_id=>[ keys %bindery_service_type_ids ] ) );
			if ( sets::exclude( [ $$self{equipment_id} ], \@equipment ) ) {
				$colour .= ' multibindery';
			} # end if
		} # end if
		if ( $Project->rush() ) {
			$colour .= ' rush';
		} # end if
	} # end if
	$colour .= ' tentative' if $$self{tentative};

	$html .= sprintf( '<li id="item_%d"%s%s>', $$self{id}, 
			( $colour ? ' class="'.$colour.'"' : '' ), 
			( $height ? ' style="height:'.$height.'px;"' : '' )
			);
	$html .= '<div class="top_row">';
	if ( $$self{project_id} ) {
		$html .= sprintf('<a class="docket" href="/employee/project/view.html?ProjectIndex=%1$d&amp;Docket=%2$d">%2$d</a>',
				$$self{project_id}, $Project->docket());
		$html .= '<div class="Company">';
		my $n = $Project->Company()->name();
		$n =~ s/The //gi;
		$html .= ssi::htmlize( $n ).'</div>';
		$html .= ' <span class="CSR">'.$Project->Company()->CSR()->firstname().'</span>' if $$Project{company_id} != $openprint::config{owner_id};

		my $Proofs_Service = $Project->Service($$services{Proofs}[0]) if $$services{Proofs} and @{$$services{Proofs}};
		if ( $Proofs_Service ) {
			my %operators = map { $$_{user_id}, $_ } $Proofs_Service->Operators();

			$html .= join(', ', map { '<span class="PrepressOperator">'.$_->User()->firstname().'</span>' } values %operators);
		} elsif ( $$Project{docket} ) {
			$openprint::log->error("NO proofs found in $$Project{id}");
		} # end if
		if ( $Project->reprint() eq 'Y' ) {
			$html .= ' REPRINT'. $Project->reprint_reason();
		} # end if
		if ( $printing_service_type_ids{$$self{servicetype_id}} ) {
			$html .= '<span class="Presses">'.join(' + ', sort( map { new openprint::Equipment($_)->strid() } @equipment ) ).'</span>' if @equipment > 1;
		} # end if
		$html .= qq`<span class="DueDate" id="JumpToDate$$self{id}">`;
		if ( ! $Project->due_date() ) {
			$html .= 'no duedate</span>';
		} else {
			my ( $year, $month, $day ) = split('-', $Project->due_date() );
			if ( $month ) { $html .= '&nbsp;'.substr( Date::Calc::Month_to_Text( $month ),0, 3); } # end if
				$html .= qq` $day</span>`;
		} # end if
		$html .= '</div>';
	} # end if project_id

	my $i_am_the_operator = sets::isin( $session{user_id}, $self->Shift()->operator_ids() )
		||
		sets::isin( $session{user_id}, [ map { $_->id() } $Equipment->Operators() ] ) 
		;
	my $is_signature = ($$self{servicetype_id} and ( ($self->ServiceType()->name() eq '') or ($self->ServiceType()->name() eq 'Signature') ) ) ? 1 : 0;

	if ( $openprint::User->Groups('Scheduling') ) {
		$html .= '<div class="middle_row">';
		$html .= '<div class="Comment" onclick="job_popup(\''.$$self{id}.'\');">'.$self->comment().'</div>';
		if ( $is_signature ) {
		  $html .= sprintf( q`<div class="Stock" onclick="popup_window('/employee/production/_stock_popup.html', 'schedule_id=%1$d', {width:475});">%2$s</div>`, $$self{id}, $self->stock() );
		  #$html .= sprintf( q`<div class="StockLocation" onclick="popup_window('/employee/production/_stock_popup.html', 'schedule_id=%1$d', {width:475});">%2$s</div>`, $$self{id}, $self->stock() );
		}
		$html .= '</div>';# middle_row
		$html .= '<div class="bottom_row">';
		$html .= '<div class="OperatorSignature">Operator Signature:</div>';
		if ( $$self{project_id} ) {
			$html .= sprintf(q`
					<input type="hidden" name="ScheduleDate-%1$d" id="ScheduleDate-%1$d" value="%2$s"/>
					<span class="Forms" onclick="job_popup('%1$d');">%3$d %4$s</span>
					`, $$self{id}, $Project->due_date(), $self->forms(), 'form'.($self->forms() > 1 ? 's' : '')
					);
			if ( $Equipment->smartscheduling() ) {
				$html .= sprintf(q`<span class="Impressions" onclick="job_popup('%1$d');">%2$d imps @ %3$d/Hr</span>`, $$self{id}, $self->impressions(), $self->speed());
			} else {
				$html .= sprintf(q`<span class="Impressions" onclick="job_popup('%1$d');">%2$d imps</span>`, $$self{id}, $self->impressions());
			} # end if
		} # end if
		if ( $Equipment->smartscheduling() or $$self{locked} ) {
			$html .= sprintf( q`<span class="StartTime" onclick="job_popup('%1$d');">Start: %2$s<img src="/images/small-%3$s.gif" alt="%3$s"/></span>`, $$self{id},
					Date::Format::time2str('%H:%M', Date::Parse::str2time($$self{starttime})),
					$$self{locked} ? 'locked' : 'unlocked',
					);
		} # end if

		$html .= sprintf( q`<span class="RunTime" onclick="job_popup('%1$d');">Total Hr: %2$.2d:%3$.2d</span>`, $$self{id}, split(':',$self->runtime()) );
			if ( $Equipment->specification('DoStockVerification') eq 'Y' ) {
				$html .= sprintf( q`<span class="StockVerified" onclick="job_popup('%1$d');">Stock: %2$s</span>`, $$self{id}, $self->stock_verified() ? 'Yes' : 'No' );
			} # end if

		if ( $$self{project_id} ) {
			$html .= '<span class="Services">';
			$html .= '<span class="Service">fold</span>' if $$services{Folding};
			$html .= '<span class="Service">stitch</span>' if $$services{SaddleStitching} or $$services{LoopStitching};
			$html .= '<span class="Service">trim</span>' if $$services{Cutting};
			$html .= '<span class="Service">no bindery</span>' if $$services{NoBindery};
			$html .= '</span>';
		}
		$html .= '<span class="Buttons">';
		if ( $$self{project_id} ) {
			$html .= ssi::button( 'Approve'.$$self{id}, {onclick=>"approve_job('$ul_id',$$self{id});", text=>'A', title=>'Approve' } ) if sets::isin( $Project->status(), 'In Prepress', 'Proofs Out','Waiting For Customer Approval','Waiting For QA Approval' );
			if ( ! $$self{locked} ) {
				$html .= ssi::button( 'Up'.$$self{id}, { onclick=>"up_job($$self{id});", text=>'&uarr;', title=>'Move Up' } );
				$html .= ssi::button( 'Down'.$$self{id}, { onclick=>"down_job($$self{id});", text=>'&darr;', title=>'Move Down' } );
			} # end if
		} # end if
		$html .= ssi::button( 'Bump'.$$self{id}, { onclick=>"popup_window('/employee/production/_bump_job.html','schedule_id=$$self{id}');", text=> 'B', title=>'Bump to next shift' } );
		if ( $$self{project_id} ) {
			$html .= ssi::button( 'Complete'.$$self{id}, { onclick=>"popup_window('/employee/production/_signature_completion_popup.html', 'schedule_id=$$self{id}', { width: '400px', height: '300px', center: 'false' } );", text=>'C',title=>'Complete Job' } );
			if ( $is_signature ) {
				$html .= ssi::button( 'House'.$$self{id}, { onclick=>"new Ajax.Updater('item_$$self{id}','_li.html', {parameters: {schedule_id:$$self{id}, action: 'House Stock' } } );", text=>'H', title=>'House Stock' } );
				$html .= ssi::button( 'PO'.$$self{id}, { target=>'_blank', href=>'/employee/purchase_order/edit.html?project_id='.$$self{project_id}, text=>'PO', title=>'Create PO' } );
			} # end if
		} # end if
		$html .= ssi::button( 'Remove'.$$self{id}, { onclick=>"remove_job($$self{id});", text=>'D', title=>'Delete from schedule' } );
		if ( $$self{project_id} ) {
			if ( ( $$self{pertains_id} and @{$$self{pertains_id}} == 2 ) or ( $$self{service_id} and @{$$self{service_id}} == 2 ) ) {
				$html .= ssi::button( 'Split'.$$self{id}, { onclick=>"split_job('$ul_id',$$self{id});", text=> 'S', title=>'Split Job' } );
			} elsif ( ( $$self{pertains_id} and @{$$self{pertains_id}} > 2 ) or ( $$self{service_id} and @{$$self{service_id}} == 2 ) ) {
				$html .= ssi::button( 'Split'.$$self{id}, { onclick=>"popup_window('_split_popup.html', 'schedule_id=$$self{id}' );", text=> 'S', title=>'Split Job' } );
			} # end if
			if ( $is_signature ) {
				$html .= ssi::button( 'Stock'.$$self{id}, { onclick=> "popup_window('/employee/production/_stock_details.html','project_id='+$$self{project_id} );", text=> 'P', title=>'Paper' } );
			} # end if
		} # end if
		if ( ( $self->starttime_seconds() > time ) or ( $$self{project_id} and ( $self->status() ne 'In Production' ) ) ) {
			$html .= ssi::button( 'Start'.$$self{id}, { onclick=> "start_job($$self{id});", text=>'Start' } );
		} elsif ( ( $self->starttime_seconds() < time ) and ( (!$$self{project_id}) or $self->status() eq 'In Production' ) ) {
			$html .= ssi::button( 'Stop'.$$self{id}, { onclick=> "stop_job($$self{id});", text=>'Stop' } );
		} # end if
		$html .= '</span>';
		$html .= '</div>';
	} else {
		$html .= sprintf( '<div class="Comment">%1$s</div>', $self->comment() );
		$html .= sprintf( '<div class="Stock">%1$s</div>', $self->stock() );
		if ( $$self{project_id} ) {
			$html .= sprintf( '<span class="Forms">%d %s</span>', $self->forms(), $self->forms() > 1 ? ' forms' : ' form' );
			$html .= sprintf( '<span class="Impressions">%d imps</span>', $self->impressions() );
		} # en dif
		$html .= sprintf( q`<span class="StartTime">Start:%2$s</span>`, $$self{id},
				Date::Format::time2str( '%H:%M', Date::Parse::str2time( $$self{starttime} ) ),
				);
		$html .= sprintf( q{<span class="RunTime">%2$.2d:%3$.2d</span>}, $$self{id}, split(':',$self->runtime()) );
		$html .= '<span class="Buttons">';
		if ( $$self{project_id} ) {
			if ( $$self{servicetype_id} and sets::isin( $self->ServiceType()->name(), [ '','Signature' ] ) ) {
				$html .= ssi::button( 'Paper'.$$self{id}, { onclick=> "popup_window('/employee/production/_stock_details.html','project_id=$$self{project_id}' );", text=> 'P', title=>'Paper' } );
			} # end if
			if ( $i_am_the_operator ) {
				$html .= ssi::button( 'Complete'.$$self{id}, { onclick=>"popup_window('/employee/production/_signature_completion_popup.html', 'schedule_id=$$self{id}', { height: '100px', center: 'false' } );", text=>'Complete', title=>'Complete Job' } );
			}
		} # end if
		if ( $i_am_the_operator ) {
			$html .= ssi::button( 'Start'.$$self{id}, { onclick=>"new Ajax.Request('_li_change.json', { parameters: { id: $$self{id}, action: 'start' } } );", text=> 'Start' } );
		} # end if
		$html .= '</span>';
		if ( $$self{project_id} ) {
			$html .= '<span class="Services">';
			$html .= '<span class="Service">fold</span>' if $$services{Folding};
			$html .= '<span class="Service">stitch</span>' if $$services{SaddleStitching} or $$services{LoopStitching};
			$html .= '<span class="Service">trim</span>' if $$services{Cutting};
			$html .= '<span class="Service">no bindery</span>' if $$services{NoBindery};
			$html .= '</span>';
		} # end if smart
	} # end if
	if ( $$self{project_id} and $openprint::session{'/employee/production/print_overview.html?show_feedback'} and ( $ul_id !~ /Pending|Approved/ ) ) {
		my @Data = openprint::ProductionFeedback->find(project_id=>$$self{project_id},order=>'starting_on');
		if ( @Data ) {
			$html .= '<br class="spacer"/><div class="Feedback"><fieldset><legend>Production Feedback</legend>
				<table><tr><th class="form">Form</th><th class="version">Version</th><th class="quantity">Quantity</th><th class="comment">Comment</th><th class="DateTime">Finished On</th></tr>
				';
			foreach my $Feedback ( @Data ) {
				my $specs = $Feedback->Service()->specs();
				$html .= sprintf('<tr><td class="form">%s</td><td class="version">%s</td><td class="quantity">%s</td><td class="comment">%s</td><td class="DateTime">%s</td></tr>',
						$$specs{SignatureIndex},
						$Feedback->version(), $Feedback->quantity(), $Feedback->comment(), 
						(Date::Format::time2str( $openprint::config{DateTimeFormat}, Date::Parse::str2time($Feedback->ending_on())),
						) );
			} # end foreach Feedback
			$html .= '</table></fieldset></div>';
		} # end if
	} # end if show Feedback

	$html .= "</li>\n";
	return $html;
} # end sub get_li

# operator_Id is not stored in the job, this is a convenience function.
sub operator_ids {
	my $self = shift;

	my $Project = $self->Project();

	if ( @_ ) {
		my @new_operator_ids = ref $_[0] eq 'ARRAY' ? @{$_[0]} : @_;
		if ( 
				(!$$self{operator_ids})
				or
				( sets::intersection( @new_operator_ids , @{$$self{operator_ids}} ) != @new_operator_ids )
			 ) {
			$$self{operator_ids} = \@new_operator_ids;

			if ( $$self{project_id} ) {
				foreach my $sig_id ( @{$$self{service_id}} ) {
					next if ! $sig_id;
					my $Service = $Project->Service( $sig_id );
					if ( $Service->service_id() != $sig_id ) {
						$openprint::log->error("Invalid service $sig_id " . $Service->to_string() );
						next;
					} # end if

					if ( sets::intersection( @new_operator_ids, $Service->operator_ids() ) != @new_operator_ids ) {
						$openprint::log->debug($Service->to_string());
						$Service->save({operator_ids=>$$self{operator_ids}});
					} # end if
				} # end foreach service_id
			} # end if project_id
		} # end if operator_ids changed
	} # end if @_

	if ( ! $$self{operator_ids} ) {
		if ( $$self{project_id} ) {
$openprint::log->debug("Servic_ids: @{$$self{service_id}}");
			foreach my $sig_id ( @{$$self{service_id}} ) {
				my $Service = $Project->Service( $sig_id );
$openprint::log->debug($Service->to_string() );
				$$self{operator_ids} = $Service->operator_ids();
			} # end foreach
		} # end if
		if ( ! ( $$self{operator_ids} and @{$$self{operator_ids}} ) ) {
			$$self{operator_ids} = $self->Shift()->operator_ids();
		}
	} # end if
	return $$self{operator_ids};
} # end sub operator_ids

sub operator_id {
	my ( $caller, undef, $line ) = caller;
	$log->error("Deprecated call to ScheduledJob::operator_id from $caller:$line");
}

sub impressions {
	my $self = shift;

	if ( @_ ) {
		$$self{impressions} = shift;
	} # end if

	if ( (!$$self{impressions}) and $$self{project_id} ) {
		my $impressions = 0;

		my $Project = $self->Project();
		if ( $self->service_id() ) {
			foreach my $sig_id ( $$self{pertains_id} ? @{$$self{pertains_id}} : @{$self->service_id()} ) {
				my $sig_specs = openprint::service::get_specs_ref( $Project, $sig_id );
				if ( ! $$sig_specs{ImpressionQuantity} ) {
					$$sig_specs{ImpressionQuantity} = $$sig_specs{'hdnImpressionQuantity'.$Project->ordered_quantity_index()};
					openprint::service::insert_service_spec( $log, $dbh, $$self{project_id}, $sig_id, 'ImpressionQuantity', $$sig_specs{ImpressionQuantity} );
				} # end if
				$impressions += $$sig_specs{ImpressionQuantity};
			} # end foreach sig
		} # end if
		$$self{impressions} = $impressions;
	} # end if
	return $$self{impressions};
} # end sub impressions

sub Project {
	my $self = shift;
	$$self{Project} = shift if @_;
	if ( ! $$self{Project} ) {
		if ( $$self{project_id} ) {
			$$self{Project} = new openprint::Project($$self{project_id});
		} elsif ( $$self{pertains_id} and @{$$self{pertains_id}} ) {
			foreach my $service_id ( @{$$self{pertains_id}} ) {
$openprint::log->debug("Guess project from service $service_id");
				my $Project_Service = openprint::Project_Service->find_one(service_id=>$service_id);
				next if ! $Project_Service;
$openprint::log->debug("Guess project from service ".$Project_Service->to_string());
				$$self{Project} = $Project_Service->Project();
				last;
			} # end foreach
			if ( $$self{Project} ) {
				$self->save({project_id=>$$self{Project}->id()});
			}
		}
	}
	if ( ! $$self{Project} ) {
		$$self{Project} = new openprint::Project( $_[0]{project_id} );
	}
	return $$self{Project};
} # end sub Project

sub runtime {
	my ( $self, $new ) = @_;
	if ( @_ == 2 ) {
		$$self{runtime} = $new;
	} # end if

	if ( ( ! $$self{runtime} ) or ( $$self{runtime} eq '00:00:00' ) ) {
		my $seconds = 0;
		if ( $$self{project_id} ) {
			my $Project = $self->Project();
			my @forms = @{$self->pertains_id()};

			foreach my $sig_id ( @{$$self{service_id}} ) {
				my $Service = $Project->Service( $sig_id );
				$seconds += $Service->runtime( $self->Equipment(), @forms > 1 ? $self->impressions()/@forms : $self->impressions(), $self->speed(), $self->pertains_id() );

				#$seconds += openprint::service::get_runtime( $Project, $sig_id, $self->Equipment(), $self->impressions()/@{$$self{service_id}}, $self->speed() );
			} # end foreach
		} # end if
		$$self{runtime} = misc::seconds2hms( $seconds );
	} # end if
	return $$self{runtime};
} # end sub runtime

sub forms {
	my ( $self ) = @_;
	return scalar @{$self->pertains_id()};
} # end sub forms

sub shift_id {
	my $Shift = $_[0]->Shift();
	return $Shift->id() if $Shift;
	return;
} # end sub shift_id


sub Shift {
	my ( $self ) = @_;

	if ( ! $$self{Shift} ) {
		my $Shift;

		if ( ! $$self{starttime} ) {
			$Shift = new openprint::Shift();
			$Shift->equipment_id( $$self{equipment_id} );
			if ( sets::isin( $self->Project()->status(), ['','In Prepress','Proofs Out','Waiting For QA Approval','Waiting For Customer Approval','Printed','Complete'] ) ) {
				$$Shift{name} = 'Pending';
			} else {
				$$Shift{name} = 'Approved';
			} # end if
		} else {
$openprint::log->debug("Getting shift for " . $self->to_string() );
			# There should only ever be 1
			my @Shifts = openprint::Shift->find({
					equipment_id		=>	$$self{equipment_id}, 
					'endtime >'			=>	$$self{starttime}, 
					'starttime <='	=>	$$self{starttime},
					#limit			=>	1,
					});
			if ( !@Shifts ) {
				$openprint::log->error("ScheduledJob: No shift for " . $self->to_string() );
if ( 0 ) {
# I'm starting to think that we shouldn't instantiate here. Or can emanantise do it all for us?

				my $limit = 12; # Only go forward 12 hours at most. 
				if ( ! @Shifts ) {
					# This attempts to instantiate a shift by adding an hour to the starttime.
					while( $limit and ! ( @Shifts = openprint::Shift::get_Shifts( $self->Equipment(),
                    DateTime->from_epoch( epoch=>$self->starttime_seconds(), time_zone=>$openprint::TZ ),
                    DateTime->from_epoch( epoch=>$self->endtime_seconds(), time_zone=>$openprint::TZ ), 
                ) ) ) {
						$self->starttime_seconds( $self->starttime_seconds() + 60*60 );
						$limit -= 1;
					} # end while
					if ( ! @Shifts ) {
						$openprint::log->warn( "No shift for $$self{starttime}" );
						return;
					}
				} # end if still ! @Shifts
				
}
			} # end if if ! @Shifts

		return if ! @Shifts;
			if ( @Shifts > 1 ) {
				$log->error("Should delete duplicate shifts! " . @Shifts );
				foreach ( @Shifts ) {
					$log->error( $_->to_string() );
					#$_->delete();
				} # end foreach
			} # end if
			$Shift = shift @Shifts;
		} # end if
		return if ! $Shift;
		$$self{Shift} = $Shift;
	} # end if
	return $$self{Shift};
} # end sub Shift

sub start {
	my ( $self ) = @_;
	my $e = $self->save({starttime_seconds=>time,locked=>1});
	if ( ! $e ) {
		if ( $$self{project_id} ) {
			foreach my $sig_id ( @{$$self{service_id}} ) {
				openprint::service::status( $$self{project_id}, $sig_id, 'In Production' );
			} # end foreach sig_id
		} # end if
	} # end if
	return $e;
} # end sub start

sub stop {
	my ( $self ) = @_;
	my $new_runtime = $self->runtime_seconds() - ( time - $self->starttime_seconds() );
	$new_runtime = 300 if $new_runtime < 0; # default to 5minutes
$log->debug("Stopping job: new runtime: $new_runtime starttime $$self{starttime} seconds: " . $self->starttime_seconds() . " now: " . time . " elapsed: " . ( time - $self->starttime_seconds() ) );
	my $e = $self->save({runtime_seconds=>$new_runtime,locked=>0});
	if ( ! $e ) {
		if ( $$self{project_id} ) {
			foreach my $sig_id ( @{$$self{service_id}} ) {
				openprint::service::status( $$self{project_id}, $sig_id, 'Ordered' );
			} # end foreach sig_id
		} # end if
	} # end if
	return $e;
} # end sub stop

sub status {
	if ( $_[0]{project_id} ) {
		my $Project = new openprint::Project($_[0]{project_id});
		foreach my $sig_id ( @{$_[0]{service_id}} ) {
			my $Service = $Project->Service( $sig_id );
			return $Service->status();
		} # end foreach sig_id
	} # end if
} # end sub status

sub bump {
	my ( $self, $equipment_id, $NewShift ) = @_;
	push @{$variable{changed}}, $self->Shift()->ul_id();
	my $Project = $self->Project();
	$Project->save({ due_date=>$Project->get_due_date()}) if $Project->id() and ! $Project->due_date();

	my $ac = sql::start_transaction( $dbh );
	$dbh->do( 'LOCK TABLE Schedule IN ACCESS EXCLUSIVE MODE' ) or $log->error( DBI->errstr );
	$dbh->do( 'LOCK TABLE Shifts IN ACCESS EXCLUSIVE MODE' ) or $log->error( DBI->errstr );

	my $Equipment = $self->Equipment();

	# If we have a change of equipment
	if ( $equipment_id and ( $equipment_id != $$self{equipment_id} ) ) {
		$self->equipment_id($equipment_id);
		# Shuffle the old list
		if ( $Equipment->smartscheduling() ) {
			openprint::employee_production::reorder_jobs(
					openprint::ScheduledJob->find(
						equipment_id				=>$$Equipment{id},
						'starttime is null'	=>0,
						order								=>'starttime',
						));
		} # end if
		$Equipment = $self->Equipment();
	} # end if

	my $error;
	if ( $Equipment->smartscheduling() ) {
# When SmartScheduling, all jobs can move. so determine the appropriate shift, sort the jobs
		if ( ! $NewShift ) {
			if ( $$self{starttime} ) {
				$NewShift = $self->Shift()->Next();
			} else {
# Have no starttime, so stick on the end of the last shift
				my $LastJob = openprint::ScheduledJob->find_one(
						order					=>	'starttime DESC NULLS LAST',
						tentative			=>	0,
						equipment_id	=>	$$self{equipment_id},
						'id !='				=>	$$self{id},
						);
				$NewShift = $LastJob->Shift();
			}
		}

		my @final_order = openprint::ScheduledJob->find(
				equipment_id	=>	$self->equipment_id(),
				'starttime <'	=>	$NewShift->starttime(),
				'id !='	=>	$$self{id},
				order=>'starttime',
				);
		foreach my $Job ( $NewShift->Schedule() ) {
			push @final_order, $Job if $$Job{id} != $$self{id};
		} # end foreach job in shift
		push @final_order, $self;
		push @final_order, openprint::ScheduledJob->find(
				equipment_id	=>	$self->equipment_id(),
				'starttime >='=>	$NewShift->endtime(),
				'id !=' 			=>	$$self{id},
				order					=>	'starttime',
				);

		# Reorder will do the saving
		openprint::employee_production::reorder_jobs( @final_order );
	} else {
		$openprint::log->debug("Not smart scheduling");
		# In non-smart scheduling, we don't touch any of the other jobs, just the one that moves.
		# If the job is scheduled, then bump to either the specified shift, or the last populated shift.
		if ( ! $NewShift ) {
			if ( $$self{starttime} ) {
				$NewShift = $self->Shift()->Next();
			} else {
				# Get the last job, and derive the shift from it.
				my $LastJob = openprint::ScheduledJob->find_one(
						order	=>	'starttime DESC',
						tentative	=>	0,
						equipment_id	=>	$$self{equipment_id},
						'id !='			=>	$$self{id},
						'starttime is null' => 0
						);
				if ( $LastJob ) {
					$NewShift = $LastJob->Shift();
				} else {
					# Find a shift > now
					$NewShift = openprint::Shift->find_one(
							equipment_id  =>  $$self{equipment_id},
							'starttime >='	=>	$parser->format_datetime(DateTime->now()),
							);
					if ( ! $NewShift ) {
						$log->error("Need to emanantise");
					}
				}
			} # end if was scheduled
		} # end if ! NewShift

		my $starttime_seconds = 0;
		my @Jobs = $NewShift->Schedule_Without_Job( $$self{id} );
		if ( @Jobs ) {
			my $LastJob = $Jobs[@Jobs-1];
			$starttime_seconds = $LastJob->endtime_seconds() + 1;
			$log->debug("Setting starttime after last job : " .$LastJob->to_string() );
		} else {
			$log->debug("No Last Job");
			$starttime_seconds = $NewShift->starttime_seconds();
		}
# This time might not fall on a shift.
		if ( $starttime_seconds < ( $_ = time ) ) {
			$openprint::log->debug("Resulting time is less than now $starttime_seconds, bumping to now $_");
			$starttime_seconds = $_;
		}

# Can't just set startime here.  Should always be a valid shift time.
# So get a shift first
		$self->starttime_seconds( $starttime_seconds );
		if ( ! $self->Shift() ) {
			$openprint::log->error("No shift");
# Fell into a spot where there are not Shifts.
# So we should 
		} # end if

		$error .= $self->save();
		my $Shift = $self->Shift();
		push @{$variable{changed}}, $Shift->ul_id() if $Shift;
	} # end if smartscheduling
	sql::end_transaction( $dbh, $ac );
	if ( $Project->id() ) {
		my @forms = map {
			my $sig_specs = openprint::service::get_specs_ref( $Project, $_ );
			$$sig_specs{SignatureIndex};
		} @{$self->service_id()} if $self->service_id();

		$Project->add_to_log( @session{'company_id','user_id'}, 'Form ' .join(',',sort @forms).' bumped to next shift: '.Date::Format::time2str($openprint::config{DateTimeFormat}, $self->starttime_seconds() ) . ' on ' . $self->Equipment()->name() );
	} # end if
	return $error;
} # end sub bump

sub speed {
	my $self = shift;
#$log->debug("Speed");
	if ( @_ ) {
		$$self{speed} = $_[0];
	} # end if
	if ( ! $$self{speed} ) {
		my $Equipment = $self->Equipment();
		if ( (!($$self{speed} = $Equipment->specification('Default Scheduling Runspeed'))) and $$self{project_id} ) {
			my $Project = $self->Project();
			my $qty_index = $Project->ordered_quantity_index();

			if ( $qty_index and $$self{service_id} and @{$$self{service_id}} ) {
				my $Service = $Project->Service( $$self{service_id}[0] );
				my $specs = $Service->specs();
				if ( ! $specs ) {
					$openprint::log->error( "$$Project{id} $$Service{service_id} has no specs?!");
					return;
				}
				my $ServiceType = $Service->ServiceType();

				if ( $ServiceType->name() eq 'Folding' ) {
					my $signatures = $self->pertains_id();
					if ( ! $signatures ) {
						$log->warn("No pertains $signatures");
					} elsif ( ! @{$signatures} ) {
						$log->warn("Empty pertains @$signatures");
					}
					$$self{speed} = openprint::Estimating::Folding::runspeed( $Project, $Service, $Equipment, $qty_index, $$signatures[0] );
				} elsif ( $ServiceType->name() eq 'Cutting' ) {
					my $signatures = $self->pertains_id();
					$$self{speed} = openprint::Estimating::Cutting::runspeed( $Project, $Service, $Equipment, $qty_index, $signatures );
				} elsif ( $ServiceType->name() eq 'SaddleStitching' ) {
				} else {
$openprint::log->debug("Getting printing speed");
					$$self{speed} = openprint::Estimating::Printing::runspeed( $Project, $specs, $qty_index, $Equipment );
				} # end if
			} # end if
		} # end if
	} # en dif
#$log->debug("DOne Speed $$self{speed}");
	return $$self{speed};
} # end sub speed

sub split {
	my ( $self, $forms ) = @_;

	my $Project = $self->Project();
	$Project->add_to_log( @openprint::session{'company_id','user_id'}, 'Splitting forms' );
	my @service_ids = $$self{pertains_id} ? @{$$self{pertains_id}} : @{$$self{service_id}};
	my $printing = ( (!($$self{pertains_id} and @{$$self{pertains_id}})) or sets::union( @{$$self{service_id}}, @{$$self{pertains_id}} ) == @{$$self{service_id}} );

$openprint::log->debug("Service ids: @service_ids");
	if ( @service_ids > 1 ) {
		if ( $forms ) {
			# Some specified # of forms
			$openprint::log->debug("forms $forms" );
			my @new_forms = splice @service_ids, @service_ids - $forms, $forms;
			if ( $printing ) {
				$self->service_id( \@service_ids );
			} # end if
			$self->pertains_id( \@service_ids );
			$self->runtime(undef);
			$openprint::log->debug("BEforesave $_");
			$_ = $self->save();
			$openprint::log->debug("After save $_");
			return if $_;

			$openprint::log->debug("About to copy");
			my $J2 = $self->copy();
			$openprint::log->debug("copy");
			if ( $self->starttime() ) {
			$openprint::log->debug("new starttime: " .$self->endtime_seconds() + 1);
				$J2->starttime_seconds( $self->endtime_seconds() + 1);
			} # end if
			$J2->pertains_id(\@new_forms);
			if ( $printing ) {
				$J2->service_id(\@new_forms);
			} # end if
			$openprint::log->debug("Runtime");
			$J2->runtime(undef);
			$openprint::log->debug("Runtime");
			$J2->save();
		} else {
			$openprint::log->debug("No forms" );
			my $runtime = int ( $self->runtime_seconds()/@service_ids );
$openprint::log->debug("RUntime seconds: $runtime");
			$self->runtime_seconds( $runtime );
			my $impressions = int( $self->impressions() / @service_ids );
			$$self{pertains_id} = [ shift @service_ids ];
			$$self{service_id} = $$self{pertains_id} if $printing;

			$self->impressions( $impressions );
			$self->save();
			my $starttime = $self->starttime_seconds() + $runtime if $self->starttime();
$openprint::log->debug("Starttime: $starttime, now: " . time);
			foreach my $s_id ( @service_ids ) {
				my $J2 = $self->copy();
				$$J2{service_id} = [ $s_id ] if $printing;
				$$J2{pertains_id} = [ $s_id ];
				if ( $self->starttime() ) {
$openprint::log->debug("Setting starttime to $starttime");
					$J2->starttime_seconds( $starttime );
					$starttime += $runtime;
				} # end if starttime
$openprint::log->debug("Asave");
				$_ = $J2->save();
$openprint::log->debug("Asave $_");
			} # end foreach 
		} # end if
	} elsif ( @service_ids ) { # == 1
		# If there is only 1 service, then we copy it, dividing al relevant values
		my $service_index = $service_ids[0];
		my $old_specs = openprint::service::get_specs_ref( $Project, $service_index );
		my $qty_index = $Project->ordered_quantity_index();

		my $NewJob = $self->copy();
		my $new_service_index = $Project->copy_signature( $old_specs, {
				'txtPrice'.$qty_index   => $$old_specs{"txtPrice$qty_index"}/2,
				}, openprint::service::status( $Project->id(), $service_index ),
				);
		$$NewJob{service_id} = [ $new_service_index ] if $printing;
		$$NewJob{pertains_id} = [ $new_service_index ];
		$NewJob->save();
# Update source service
		openprint::service::insert_service_spec( $log, $dbh, $Project->id, $service_index, "txtPrice$qty_index", $$old_specs{"txtPrice$qty_index"}/2 );

	} # end if
} # end sub split

sub to_string {
	my $self = $_[0];
	return sprintf('%d %s on %s starting %s', $self->docket(), join(',', ( $self->service_id() ? @{$self->service_id()} : () ) ), $self->Equipment()->name(), $self->starttime() );
} # end sub to_string

sub pertains_id {
	
	if ( @_ > 1 ) {
		$_[0]{pertains_id} = $_[1];
	} # end if
	if ( (! $_[0]{pertains_id} ) and $_[0]{service_id} ) {
		return $_[0]{service_id};
	} # end if
	if ( $_[0]{pertains_id} ) {
		return $_[0]{pertains_id};
	} # end if
	return [];
} # end sub pertains_id

sub ServiceType {
	return new openprint::ServiceType( $_[0]{servicetype_id} );
} # end sub ServiceType

sub equipment_id {
	if ( @_ > 1 ) {
		if ( $_[0]{equipment_id} != $_[1] ) {
			$_[0]{equipment_id} = $_[1];
			delete $_[0]{Shift};
			delete $_[0]{Equipment};
		}
	} # end if
	if ( ( ! $_[0]{equipment_id} ) and $_[0]{project_id} ) {
		# Attempt to guess
		my $Project = $_[0]->Project();
		if ( $_[0]{service_id} and @{$_[0]{service_id}} ) {
			my $Service = $Project->Service( $_[0]{service_id}[0] );
			my $specs = $Service->specs();

			if ( sets::isin( $Service->ServiceType()->name(), [ '', 'Signature' ] ) ) {
				my $press = $$specs{UsePress} ? $$specs{UsePress} : $$specs{'ddmPress'.$Project->ordered_quantity_index()};
				if ( $press ) {
					my $Equipment = openprint::Equipment->find_one( strid => ( $$specs{UsePress} ? $$specs{UsePress} : $$specs{'ddmPress'.$Project->ordered_quantity_index()} ) );
					$_[0]{equipment_id} = $Equipment->id() if $Equipment;
				} # end if
			} elsif ( sets::isin( $Service->ServiceType()->name(), ['SaddleStitching','LoopStitching'] ) ) {
				$_[0]{equipment_id} = $$specs{'ddmEquipment'.$Project->ordered_quantity_index()};
			} # end if
		} # end if services
	} # end if need to load and has a project
	return $_[0]{equipment_id};
} # end sub equipment_id

sub approve {
	my $Project = $_[0]->Project();
	if ( ! $Project->id() ) {
		return "Invalid project specified for approve job";
	} # end if
	my $services = $Project->services();
	if ( ! ( $$services{Proofs} or $$services{FilmStripping} ) ) {
		push @{$$services{Proofs}}, $Project->add_service( 'Proofs' );
	} # end if
	require openprint::employee_project;
	openprint::employee_production::mark_proofs_approved( $Project );
	openprint::employee_project::send_proofs_approved_email( $Project->id() );
	#sql::update( $log, $dbh, 'tbl_Project_Contents', ['lngProjectIndex=? AND strStatus=?', $Project->id(), 'Waiting For Customer Approval'], 'strStatus', 'Complete' );
	$Project->add_to_log( @session{'company_id','user_id'}, 'Approved from schedule' );
	$Project->update_status();
	return;
} # end sub approve

sub put_job_on_schedule {
	my ( $Job ) = @_;

	if ( ! $Job->starttime_seconds() ) {
		# Stick the start time at the end or now.
		my $LastJob = openprint::ScheduledJob->find_one(
				'starttime is null' =>  0,
				equipment_id  =>  $$Job{equipment_id},
				order         =>  'starttime desc',
				tentative     =>  0,
				);
		if ( $LastJob ) {
			$Job->starttime_seconds( $LastJob?$LastJob->endtime_seconds()+1: time );
		}
		
	}
	if ( $Job->starttime_seconds() < time ) {
		$Job->starttime_seconds( time );
	}
	if ( ! $Job->Shift() ) {
		# There is no shift for this time period.
		# So get the next shift after and put it on there.
		# If no shifts, then will have to fall back to Pending
		my $NextShift = openprint::Shift->find(
				equipment_id	=>	$$Job{equipment_id},
				'starttime <='	=>	$Job->starttime(),
				'endtime >'	=>	$Job->starttime(),
				);
		if ( $NextShift ) {
			$Job->starttime( $$NextShift{starttime} );
		} else {
			$Job->starttime(undef);
		}
	}
	$Job->save();
	# Since we stuck it on the end, we don't need to reorder
	#$Job->reorder_shift();
} # end sub put_job_on_schedule

sub docket {
	if ( ! $_[0]{docket} ) {
		if ( $_[0]{project_id} ) {
			$_[0]{docket} = $_[0]->Project()->docket();
		} else {
			$openprint::log->debug("No project id for job $_[0]{id} so no docket");
		}
	}
	return $_[0]{docket};
}

1;
__END__
