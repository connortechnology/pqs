package openprint::pageflip;
use strict;
use openprint ();

use vars qw( $log $dbh %param %config %variable );
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*param = \%openprint::param;
*config = \%openprint::config;
*variable = \%openprint::variable;

require openprint::PageFlip;
require openprint::PageFlip_Page;

sub view {
	$variable{'PageFlip'} = new openprint::PageFlip($param{'pageflip_id'});

	if ( $param{'docket'} ) {
		my $PageFlip = openprint::PageFlip->find_one('docket'=>$param{'docket'});
		if ( ! $PageFlip ) {
			my $Project = openprint::Project->find_one('docket'=>$param{'docket'});
			if ( ! $Project ) {
				$variable{'error'} .= "Invalid docket $param{'docket'}";
				return;
			} # end if

			$PageFlip = new openprint::PageFlip();
			$variable{'error'} .= $PageFlip->save({
					'docket'		=>	$param{'docket'},
					'company_id'	=>	$Project->company_id()
					});
		} # end if
		$variable{'PageFlip'} = $PageFlip; 
	} # end if docket
	if ( ! $variable{'PageFlip'}->Pages() ) {
		$variable{'error'} .= get_files( $variable{'PageFlip'} );
	} # end if
	if ( $param{'command'} eq 'Save' ) {
		my $Page = new openprint::PageFlip_Page( $param{'page_id'} );
		$variable{'error'} .= $Page->save(\%param);
		$variable{'error'} .= $Page->writeImage();
		if ( $param{'save_to_all'} ) {
			foreach my $P ( $variable{'PageFlip'}->Pages() ) {
				next if $P->id() == $Page->id();
				next if $P->src_width() != $Page->src_width();
				next if $P->src_height() != $Page->src_height();
				next if $P->width() != $Page->width();
				next if $P->height() != $Page->height();
				$P->save({'crop_box'=>$Page->crop_box()});
				$P->writeImage();
			} # end foreach P
		} # end if
	} # end if
} # end sub view

sub get_files {
	my ( $PageFlip ) = @_;
	my $error;

# Go looking for files.
	my @filenames;
	if ( opendir DIRHANDLE, $config{'PageFlipDir'}.'/LR' ) {
		@filenames = readdir DIRHANDLE;
		closedir DIRHANDLE;
	} else {
		$log->error( "Cannot open $config{'PageFlipDir'}" );
	} # end if
	$log->debug("# of files read " . @filenames );
	my @pages;
	foreach my $file ( @filenames ) {
	   if ( $file =~ /^$param{'docket'}/ ) {
		   push @pages, $file;
	   } # end if
	} # end foreach
	@pages = sort @pages;
	foreach my $file ( @pages ) {
		my ( $docket, $page ) = $file =~ /^(\d+).+p(\d+).+$/;
		if ( ! $page ) {
			$error .= "Unable to parse filename $file<br/>";
			next;
		} # end id
		my $Page = new openprint::PageFlip_Page();
		$error .= $Page->save({
			'pageflip_id'	=>	$PageFlip->id(),
			'filename'	=>	$file,
			'page'		=>	$page,
		});
		delete $$PageFlip{'Pages'};
	} # end foreach file
	return $error;
} # end sub get_files

sub edit {
	$variable{'PageFlip'} = new openprint::PageFlip($param{'pageflip_id'});
} # end sub edit

sub _page {
	$variable{'Page'} = new openprint::PageFlip_Page($param{'page_id'});
} # end sub _page

1;
__END__
