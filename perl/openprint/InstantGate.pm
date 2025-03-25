use strict;
package openprint::InstantGate;

use openprint ();
my $debug = 0;

sub find {
	my %params = @_;
	my @clauses;
	my @values;
	my %results;

	if ( $params{'equipment_id'} ) {
		push @clauses, 'equipment_id=?';
		push @values, $params{'equipment_id'};
	} # end if
	if ( $params{'created_on'} ) {
		push @clauses, 'created_on=?';
		push @values, $params{'created_on'};
	} # end if
	if ( $params{'created_on_start'} and $params{'created_on_end'} ) {
		push @clauses, 'created_on BETWEEN ? AND ?';
		push @values, @params{'created_on_start','created_on_end'};
	} elsif ( $params{'created_on_start'} ) {
		push @clauses, 'created_on >= ?';
		push @values, $params{'created_on_start'};
	} elsif ( $params{'created_on_end'} ) {
		push @clauses, 'created_on <= ?';
		push @values, $params{'created_on_end'};
	} # end if
	if ( $params{'Timestamp'} ) {
		push @clauses, 'created_on=?';
		push @values, sprintf('%.4d-%.2d-%.2d %.2d:%.2d:%.2d', $params{'Timestamp'} =~ /(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/ );
	} # end if
	my $data = $openprint::dbh->selectall_arrayref('SELECT * FROM InstantGate_020_Messages WHERE '.join(' AND ', @clauses ), { Slice => {} }, @values );
	if ( ! $data ) {
$openprint::log->error('Error loading InstantGate_020_Messages' . $openprint::dbh->errstr());
return;
	} elsif ( $debug ) {
$openprint::log->debug("Loading InstantGate_020_Messages (@clauses) (@values): " . @$data . ' records returned');
	} # end if
	foreach (@$data) {
		$results{$_->{'created_on'}} = $_;
	} # end foreach
	return \%results;
} # end sub find

sub create_job_file {
	my ( $Project ) = @_;

	if ( ! open ( FH, $openprint::configuration{'InstantGateJobFilesTODC'}.'/file.job' ) ) {
		$openprint::log->error("Unable to create Job File $openprint::configuration{'InstantGateJobFilesTODC'}/file.job Reason($!)" );
	} # end if
	print FH "[Header]\n";
	print FH "SenderID=ConnorTechnology\n";
	print FH "Software=IntelligentQuote\n";
	print FH "Version=3\n";
	print FH "Release=0\n";
	print FH "\n";
	print FH "[Order]\n";
	print FH sprintf("OrderNo=\%d\n", $Project->docket() );
	print FH sprintf("CustomerName=\%s\n", $Project->Company()->name() );
	print FH sprintf("DeliveryAmount=\%s\n", $Project->ordered_quantity() );

	my $prod_id = 0;
	foreach my $sig_id ( $Project->signatures() ) {
		my $sig_specs = openprint::service::get_specs_ref( $Project->id, $sig_id );
		my $Paper = openprint::Paper::load_from_signature( $Project, $sig_specs );
		print FH "\n";
		print FH sprintf("[Prod%3d]\n", $prod_id );
		#print FH, sprintf("ProdNo=\%d\n", $Project->id() );
		print FH sprintf("Width=\%d\n", $Paper->width()*25.4 ); # in mm
		print FH sprintf("Height=\%d\n", $Paper->height()*25.4 );
		print FH sprintf("PaperNameShort=\%s\n", $Paper->name() );
		print FH sprintf("PaperTypeName=\%s\n", $Paper->finish() );
		print FH sprintf("PaperGrammage=\%d\n", $Paper->gsm() );
		print FH sprintf("PaperVolume=\%s\n", ($Paper->calliper()*25.4/$Paper->gsm())*1000 );
		print FH "\n";
		print FH sprintf("[Job%3d]\n", $prod_id );
		print FH sprintf("JobNo\n", $prod_id );
		print FH sprintf("JobName\n", $Project->Type()->name() );
		my $sheets = $$sig_specs{'txtPressSheetQty'.$Project->ordered_quantity()};
		$sheets =~ s/\D//g;
		print FH sprintf("Volume\n", $sheets );

		my @schedule = openprint::press_schedule->find('project_id'=>$Project->id(),'service_id'=>$sig_id);
		my $schedule = shift @schedule;
		
		my ( $year, $month, $day, $hours, $minutes, $seconds ) = $$schedule{'starttime'} =~ /(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)/;

		print FH sprintf("StartDate=%.4d%.2d%.2d\n", $year, $month, $day );
		print FH sprintf("StartTime=%.2d%.2d\n", $hours,$minutes );
		print FH "\n";
		print FH "ML3100\n";
		
		$prod_id += 1;
	} # end foreach
} # end sub create_job_file

sub Parse_001 {
} # end sub Parse_001
sub Parse_011 {
} # end sub Parse_011
sub Parse_011 {
} # end sub Parse_011
sub ParseRecord {
	my ( $Equipment, @record ) = @_;
	if ( $record[0] eq 'REC001' ) {
		my ( $rec, $Timestamp, $ActivityNo, $PersNo, $LastName, $FirstName, $Note, $WorkPlaceNo ) = @record;
	} elsif ( $record[0] eq 'REC011' ) {
		my ( $rec, $Timestamp, $MatNo, $MatName, $MatAmount, $OrderNo, $ProdNo, $JobNo, $MatUnit, $Note, $PersNo, $WorkPlaceNo, $ProductionTypeNo ) = @record;
	} elsif ( $record[0] eq 'REC020' ) {
$openprint::log->debug("Got a REC020");
		my ( $rec, $Timestamp, $OrderNo, $ProdNo, $JobNo, $WorkPlaceNo, $ActivityNo, $ActivityValue, $ActivityName, $Amount, $TotalCount, $Units  ) = @record;
$openprint::log->debug("Timestamp $Timestamp");
		my $t = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:%.2d', $Timestamp =~ /(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/ );
		if ( ! sql::execute( undef, undef, q{SELECT * FROM InstantGate_020_Messages WHERE equipment_id=? AND created_on=?}, $Equipment->id(), $t ) ) {

			sql::insert(undef, undef, 'InstantGate_020_Messages', { 'equipment_id'=>$Equipment->id(),
					'created_on'	=>	$t,
					'OrderNo'		=>	$OrderNo eq '' ? undef : $OrderNo,
					'ProdNo'		=>	$ProdNo eq '' ? undef : $ProdNo,
					'JobNo'			=>	$JobNo eq '' ? undef : $JobNo,
					'WorkPlaceNo'	=>	$WorkPlaceNo eq '' ? undef : $WorkPlaceNo,
					'ActivityNo'	=>	$ActivityNo eq '' ? undef : $ActivityNo,
					'ActivityValue'	=>	$ActivityValue eq '' ? undef : $ActivityValue,
					'ActivityName'	=>	$ActivityName eq '' ? undef : $ActivityName,
					'Amount'		=>	$Amount eq '' ? undef : $Amount,
					'TotalCount'	=>	$TotalCount eq '' ? undef : $TotalCount,
					'Units'			=>	$Units eq '' ? undef : $Units,
					} );
		} # end if
	} # end if	
} # end sub ParseRecord 

1;
__END__
