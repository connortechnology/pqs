use strict;
package openprint::employee_sred;

use openprint ();
use vars qw( $r %variable %session %param %config $log $dbh );
*variable = \%openprint::variable;
*session = \%openprint::session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

require openprint::SRED_Project;
require HTML::FormatText;

sub projects {
	if ( $param{'action'} eq 'Save' ) {
		my $Project = new openprint::SRED_Project($param{'project_id'});
		#$Project->set({'created_by'=>$session{'user_id'}}) if ! $Project->id();
		$variable{'error'} .= $Project->save( {'name' => $param{'name'}, 'description' => $param{'description'} } );
		%param = ();
	} elsif ( $param{'action'} eq 'Export' ) {
		my $Project = new openprint::SRED_Project($param{'project_id'});

		my $tmp_path = '/tmp/sred-'.time;
		if ( ! mkdir ( $tmp_path ) ) {
			$variable{'error'} .= "Unable to make temporary directory. Reason: $!";
			return;
		} # end if
		my @files;
		
		my $formatter = HTML::FormatText->new();
		my @header = ( 'Type', ( $param{'project_id'} ? () : ( 'Project' ) ), 'Starting','Ending','Duration','All Day','Time Known', 'Personnel', 'Evidence', 'Description','Cost', 'Cost Units', 'Quantity', 'Quantity Units', 'Weight', 'Weight Units', 'Total' );
		my @data;
		foreach my $C ( openprint::SRED_Content->find( 
			ssi::date_filter('created_on_start', 'created_on >='),
			ssi::date_filter('created_on_end', 'created_on <='),
			ssi::date_filter('updated_on_start', 'updated_on >='),
			ssi::date_filter('updated_on_end', 'updated_on <='),
			( $param{'project_id'} ? ( 'project_id'=>$param{'project_id'} ) : () ) ) 
				) {
			push @data, ( $C->Type()->name(), 
				( $param{'project_id'} ? () : ( $C->Project()->name() ) ),
				$C->starting(), $C->ending(), $C->duration(), $C->all_day_event(), $C->unknown_time(), 
				$C->User()->name(),
				join(',',map { $_->url() } $C->Assets() ),
				$formatter->format_string($C->description()),
				$C->cost(), $C->cost_units(),
				$C->quantity(), $C->quantity_units(),
				$C->weight(), $C->weight_units(),
				$C->total(),
				);
			foreach my $A ( $C->Assets() ) {
				my $Asset = $A->Asset();
				if ( ! symlink $Asset->on_disk_path(), $tmp_path.'/'.$Asset->on_disk_filename() ) {
					$variable{'error'} .= 'Error linking Asset ' . $Asset->on_disk_path() . ' to ' . $tmp_path.'/'.$Asset->on_disk_filename().", reason: $!<br/>";
				} else {
					push @files, $tmp_path.'/'.$Asset->on_disk_filename();
				} # end if
			} # end foreach $Asset
		} # end foreach C

		misc::save_file( $log, $tmp_path.'/'.($param{'project_id'} ? $Project->name() : 'SRED' ).'.csv', join('',misc::data_to_csv(\@header, \@data )));
		push @files, $tmp_path.'/'.($param{'project_id'} ? $Project->name() : 'SRED' ).'.csv';
$log->debug("Zipping zip -r $tmp_path.zip $tmp_path/");
		if ( system( "zip -j -1 -r $tmp_path.zip $tmp_path/" ) ) {
			$variable{'error'} .= "Unable to create zip. Reason: $!<br/>";
		} else {
			push @files, $tmp_path.'.zip';
			misc::export( $r, $log, \%variable, ($param{'project_id'} ? $Project->name() : 'SRED' ).'.zip', [ misc::load_file( $log, "$tmp_path.zip" ) ] );
		} # end if

		#Cleanup
		foreach ( @files ) {
		unlink $_;
		} # end foreach
		rmdir $tmp_path;
	} elsif ( $param{'action'} eq 'Delete' ) {
		my $Project = new openprint::SRED_Project( $param{'project_id'} );
		$variable{'error'} .= $Project->delete();
		%param = ();
	} else {
		ssi::save_params( '/employee/sred/projects.html', ( 
			'created_on_start_year','created_on_start_month','created_on_start_day',
			'created_on_end_year','created_on_end_month','created_on_end_day',
			'user_id',
			) );
	} # end if
} # end sub projects
sub _projects {
	ssi::save_params( '/employee/sred/projects.html', ( 
		'created_on_start_year','created_on_start_month','created_on_start_day',
		'created_on_end_year','created_on_end_month','created_on_end_day',
		'user_id',
		) );
} # end sub _projects

sub history {
	if ( $param{'btnFunction'} eq 'Save' ) {
		$param{'owner_id'} = $session{'company_id'} if ! $param{'owner_id'};
		$param{'starting'} = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:00', @param{'starting_year','starting_month','starting_day','starting_hour','starting_minute'} );
		$param{'ending'} = sprintf('%.4d-%.2d-%.2d %.2d:%.2d:00', @param{'ending_year','ending_month','ending_day','ending_hour','ending_minute'} );
		if ( ! $param{'timetrack_id'} ) {
			if ( openprint::Timetrack->find_one('owner_id'=>$param{'owner_id'},'company_id'=>$param{'company_id'},'starting'=>$param{'starting'},'ending'=>$param{'ending'},'service_id'=>$param{'service_id'}) ) {
				$variable{'error'} = 'Not creating duplicate.<br/>';
				return;
			} # end if
		} # end if
		my $Timetrack = new openprint::Timetrack( $param{'timetrack_id'} );
		$variable{'error'} .= $Timetrack->save(\%param);
		if ( $param{'referrer_invoice_id'} ) {
			$_ = $param{'referrer_invoice_id'};
			%param = ();
			$param{'invoice_id'} = $_;
			$variable{'Redirect'} = '/invoice/edit.html';
		} else {
			ssi::save_params( '/timetrack/edit.html', 'ending', 'company_id' );
		} # end if
	} elsif ( $param{'btnFunction'} eq 'Destroy' ) {
		my $Timetrack = new openprint::Timetrack( $param{'timetrack_id'} );
		$variable{'error'} .= $Timetrack->destroy();
	} elsif ( $param{'action'} eq 'reset' ) {
		foreach ( 'starting_start_year','starting_start_month','starting_start_day','starting_end_year','starting_end_month','starting_end_day','invoiced','paid','user_id','company_id', 'service_id', 'lastupdated' ) {
			delete $session{'/timetrack/history.html?'.$_}
		} # end foreach
	} elsif ( ! $param{'btnFunction'} ) {
		ssi::save_params( '/timetrack/history.html', ( 'starting_start_year','starting_start_month','starting_start_day','starting_end_year','starting_end_month','starting_end_day','invoiced','paid','user_id','company_id', 'service_id') );
	} # end if

	if ( ( ! $session{'/timetrack/history.html?lastupdated'} ) or ( time - $session{'/timetrack/history.html?lastupdated'} ) > ( 12*60*60 ) ) {
		ssi::setup_date_select( '/timetrack/history.html', 'starting_start', -31 );
		ssi::setup_date_select( '/timetrack/history.html', 'starting_end', '' );
	} # end if

	$session{'/timetrack/history.html?invoiced'} = '0' if ! $session{'/timetrack/history.html?invoiced'};
	$session{'/timetrack/history.html?paid'} = '0' if ! $session{'/timetrack/history.html?paid'};
	if ( sets::isin( $session{'user_type'}, ['A','E'] ) ) {
		$session{'/timetrack/history.html?user_id'} = $session{'user_id'} if ! exists $session{'/timetrack/history.html?user_id'};
	} # end if
} # end sub history

sub _history {
	if ( ! $param{'btnFunction'} ) {
		ssi::save_params( '/timetrack/history.html', ( 'starting_start_year','starting_start_month','starting_start_day','starting_end_year','starting_end_month','starting_end_day','invoiced','paid','user_id','company_id', 'service_id') );
	} # end if
} # end sub _history

sub project {
	my $Project = $variable{'Project'} = new openprint::SRED_Project( $param{'project_id'} );
	if ( $param{'action'} eq 'Save' ) {
		$Project->set({'created_by'=>$session{'user_id'}}) if ! $Project->id();
		$variable{'error'} .= $Project->save( {'name' => $param{'name'}, 'description' => $param{'description'} } );
		%param = ();
	} elsif ( $param{'action'} eq 'Copy' ) {
		$variable{'Project'} = $Project = $Project->copy();
		$variable{'error'} .= $Project->save();
	} elsif ( $param{'action'} eq 'Export' ) {
		
		my $tmp_path = '/tmp/sred-'.time;
		if ( ! mkdir ( $tmp_path ) ) {
			$variable{'error'} .= "Unable to make temporary directory. Reason: $!";
			return;
		} # end if
		my @files;
		my @header = ( 'Starting','Ending','Duration','All Day','Time Known', 'Personnel', 'Evidence', 'Description' );
		my @data;
		my $formatter = HTML::FormatText->new();
		foreach my $C ( $Project->Contents() ) {
$log->debug("Pre format " . $C->description() );
$log->debug("APre format " . $formatter->format_string($C->description() ) );
			push @data, ( $C->starting(), $C->ending(), $C->duration(), $C->all_day_event(), $C->unknown_time(), 
				join(',',map { $_->name() } $C->Personnel() ), 
				join(',',map { $_->url() } $C->Assets() ),
				$formatter->format_string($C->description()),
				);
			foreach my $A ( $C->Assets() ) {
				my $Asset = $A->Asset();
				if ( ! symlink $Asset->on_disk_path(), $tmp_path.'/'.$Asset->on_disk_filename() ) {
					$variable{'error'} .= 'Error linking Asset ' . $Asset->on_disk_path() . ' to ' . $tmp_path.'/'.$Asset->on_disk_filename().", reason: $!<br/>";
				} else {
					push @files, $tmp_path.'/'.$Asset->on_disk_filename();
				} # end if
			} # end foreach $Asset
		} # end foreach C
		#misc::export_csv( $r, $log, \%variable, $Project->name().'.csv', \@header, \@data );
		misc::save_file( $log, $tmp_path.'/'.($param{'project_id'} ? $Project->name() : 'SRED' ).'.csv', join('',misc::data_to_csv(\@header, \@data )));
		push @files, $tmp_path.'/'.($param{'project_id'} ? $Project->name() : 'SRED' ).'.csv';
$log->debug("Zipping zip -r $tmp_path.zip $tmp_path/");
		if ( system( "zip -j -1 -r $tmp_path.zip $tmp_path/" ) ) {
			$variable{'error'} .= "Unable to create zip. Reason: $!<br/>";
		} else {
			push @files, $tmp_path.'.zip';
			misc::export( $r, $log, \%variable, $Project->name().'SRED.zip', [ misc::load_file( $log, "$tmp_path.zip" ) ] );
		} # end if

		#Cleanup
		foreach ( @files ) {
		unlink $_;
		} # end foreach
		rmdir $tmp_path;
	} elsif ( $param{'action'} eq 'Upload' ) {
		foreach my $C ( $Project->Contents() ) {
			next if ! $param{'filename-'.$$C{id}};

			my $Asset = new openprint::Asset();
			$variable{'error'} .= $Asset->save( { 'filename' => $param{"filename-$$C{id}"} } );
			if ( ! $variable{'error'} ) {
				$variable{'information'} .= 'Information successfully stored.<br/>';
			} # end if
			my $upload = $r->upload('filename-'.$$C{id});
            if ( ! $upload ) {
                $variable{'error'} .= "There was no upload for $param{'filename-'.$$C{id}}<br/>";
                $Asset->save({'filename'=>''});
				next;
            } elsif ( ! $upload->link( $Asset->on_disk_path() ) ) {
                $variable{'error'} .= "There was an error saving file $param{'filename-'.$$C{id}} to " . $Asset->on_disk_path() . ": $!<br/>";
                $Asset->save({'filename'=>''});
				next;
			} # end if
			$variable{'information'} .= "File $param{'filename-'.$$C{id}} was uploaded successfully.<br/>";
			if ( $Asset->id() ) {
				my $SRED_Asset = new openprint::SRED_Asset();
				$variable{'error'} .= $SRED_Asset->save({'content_id'=>$$C{'id'},'asset_id'=>$$Asset{'id'}});
			} # end if
		} # end foreach
        %param = ();
	} elsif ( $param{'action'} eq 'SaveContent' ) {
		my $Content;
		my $Duration = DateTime::Duration->new(
				'days'=>$param{'duration-'.$param{'content_id'}.'_days'}, 
				'hours'=>$param{'duration-'.$param{'content_id'}.'_hours'}, 
				'minutes' =>$param{'duration-'.$param{'content_id'}.'_minutes'} ) if $param{'duration-'.$param{'content_id'}.'_days'} or $param{'duration-'.$param{'content_id'}.'_hours'} or $param{'duration-'.$param{'content_id'}.'_minutes'};
		if ( ( ! $param{'content_id'} ) and $Content = openprint::SRED_Content->find_one(
					'project_id'	=>	$param{'project_id'},
					'user_id'		=>	$param{'user_id-'.$param{'content_id'}},
					'description'	=>	$param{'description-'.$param{'content_id'}},
					'notes'         =>  $param{'notes-'.$param{'content_id'}},
					( Date::Calc::check_date( @param{map { 'starting-'.$param{'content_id'}.'_'.$_ } ( 'year','month','day' )} ) ?
					  ( 'starting'		=>	sprintf('%.4d-%.2d-%.2d %.2d:%.2d:00', @param{map { 'starting-'.$param{'content_id'}.'_'.$_ } ( 'year','month','day','hour','minute') } ) ) : () ),
					( Date::Calc::check_date( @param{map { 'ending-'.$param{'content_id'}.'_'.$_ } ( 'year','month','day' )} ) ?
					  ( 'ending'		=>	sprintf('%.4d-%.2d-%.2d %.2d:%.2d:00', @param{map { 'ending-'.$param{'content_id'}.'_'.$_ } ( 'year','month','day','hour','minute') } ) ) : () ),
					'duration'		=>	( $Duration ? DateTime::Format::Pg->format_interval( $Duration ) : undef ),
					'docket'        =>  ( $param{'docket-'.$param{'content_id'}} ? $param{'docket-'.$param{'content_id'}} : undef ),
					'type_id'		=>	$param{'type_id-'.$param{'content_id'}},
					'mweight'		=>	( $param{'mweight-'.$param{'content_id'}} ? $param{'mweight-'.$param{'content_id'}} : undef ),
					'quantity'		=>	( $param{'quantity-'.$param{'content_id'}} ? $param{'quantity-'.$param{'content_id'}} : undef ),
					'quantity_units'		=>	$param{'quantity_units-'.$param{'content_id'}},
					'weight'		=>	( $param{'weight-'.$param{'content_id'}} ? $param{'weight-'.$param{'content_id'}} : undef ),
					'total'			=>	( $param{'total-'.$param{'content_id'}} ? $param{'total-'.$param{'content_id'}} : undef ),
					) ) {
			$variable{'error'} .= 'Duplicate found.  Not saving.';
		} else {
			$Content = new openprint::SRED_Content( $param{'content_id'} );
			save_content( $Content );
		} 
		$variable{'Project'} = $Content->Project();
	} # end if
} # end sub project
sub save_content {
	my ( $Content ) = @_;
	my $suffix = '-'.$$Content{'id'};

	foreach my $field ( keys %openprint::SRED_Content::fields ) {
		if ( exists $param{$field.$suffix} ) {
			$Content->$field( $param{$field.$suffix} );
		} elsif ( Date::Calc::check_date( @param{map { $field.$suffix.'_'.$_ } ( 'year','month','day' )} ) ) {
			$Content->$field( sprintf('%.4d-%.2d-%.2d %.2d:%.2d:00', @param{map { $field.$suffix.'_'.$_ } ( 'year','month','day','hour','minute') } ) );
		} elsif ( $param{$field.$suffix.'_days'} or $param{$field.$suffix.'_hours'} or $param{$field.$suffix.'_minutes'} ) {
			my $Interval = DateTime::Duration->new(
					'days'=>$param{$field.$suffix.'_days'},
					'hours'=>$param{$field.$suffix.'_hours'},
					'minutes' =>$param{$field.$suffix.'_minutes'} );
			$Content->$field( DateTime::Format::Pg->format_interval( $Interval ) );
		} else {
			$log->warn("Unknown field $field");
		} # end if
	} # end foreach
	$variable{'error'} .= $Content->save({ 'project_id'	=>	$param{'project_id'} });
	if ( $param{'filename'} ) {
		my $Asset = openprint::Asset::upload( $param{'filename'} );
		if ( ! $Asset ) {
			$variable{'error'} .= $!;
		} else {
			$variable{'information'} .= "File $param{'filename'} was uploaded successfully.<br/>";
		} # end if

		if ( $Asset and $Asset->id() ) {
			my $SRED_Asset = openprint::SRED_Asset->find_one('content_id'=>$$Content{'id'},'asset_id'=>$$Asset{'id'});
			if ( ! $SRED_Asset ) {
				$SRED_Asset = new openprint::SRED_Asset();
				$variable{'error'} .= $SRED_Asset->save({'content_id'=>$$Content{'id'},'asset_id'=>$$Asset{'id'}});
			} # end if
		} # end if
	} # end if filename
} # end sub save_content

sub _contents {
	my $Project = $variable{'Project'} = new openprint::SRED_Project( $param{'project_id'} );
	if ( $param{'action'} eq 'delete' ) {
		my $Content = new openprint::SRED_Content( $param{'content_id'} );
		$variable{'error'} .= $Content->delete();
	} elsif ( $param{'action'} eq 'copy' ) {
		my $Content = new openprint::SRED_Content( $param{'content_id'} );
		$Content = $Content->copy();
		$variable{'error'} .= $Content->save();
	} # end if
} # end sub _contents

sub _description {
	my $Content = $variable{'Content'} = new openprint::SRED_Content( $param{'id'} );
	if ( $param{'action'} eq 'update' ) {
		$variable{'error'} .= $Content->save({'description'=>$param{'value'}});
	} # end if
} # end sub _description

sub _date_edit {
	my $Object = $variable{'Object'} = ('openprint::'.$param{'object_type'})->new( $param{'object_id'} );
	if ( $param{'action'} eq 'save' ) {
		$Object->save({
			$param{field} => sprintf('%.4d-%.2d-%.2d %.2d:%.2d:%.2d', @param{map { $param{'field'}.'_'.$_ } ( 'year','month','day','hour','minute' ) } ),
			} );
	} # end if
} # end sub _date_edit

sub _content_edit {
	my $C = $variable{'C'} = new openprint::SRED_Content( $param{'content_id'} );
	$variable{'Project'} = $C->Project();
} # end sub _content_edit
sub _content_view {
	my $Content = $variable{'C'} = new openprint::SRED_Content( $param{'content_id'} );
	$variable{'Project'} = $Content->Project();
	if ( $param{'action'} eq 'Save' ) {
		save_content( $Content );
	} # end if
} # end sub _content_edit

sub _content_edit_Other {
	$variable{'C'} = new openprint::SRED_Content( $param{'content_id'} );
	$variable{'C'}->id( $param{'content_id'} );
} # end sub _content_Other
sub _content_edit_Stock {
	$variable{'C'} = new openprint::SRED_Content( $param{'content_id'} );
	$variable{'C'}->id( $param{'content_id'} );
} # end sub _Content_Stock
sub _content_edit_Time {
	$variable{'C'} = new openprint::SRED_Content( $param{'content_id'} );
	$variable{'C'}->id( $param{'content_id'} );
} # end sub _content_Time

sub _assets {
	my $Content = $variable{'C'} = new openprint::SRED_Content( $param{'content_id'} );
	if ( $param{'action'} eq 'delete' ) {
		my $Asset= new openprint::SRED_Asset( {'content_id'=>$param{'content_id'},'asset_id'=>$param{'asset_id'} } );
		$variable{'error'} .= $Asset->delete();
	} # end if
} # end sub _assets

1;
__END__
