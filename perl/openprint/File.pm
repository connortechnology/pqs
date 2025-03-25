use strict;
package openprint::File;
our @ISA = qw( openprint::Object );
require misc;

use vars qw( $debug $table $serial %fields %transforms %defaults );

$debug = 0;
$table = 'project_files';
$serial = 'project_files_id_seq';
%fields = (
	id			=>	'id',
	project_id	=>	'project_id',
	filename	=>	'filename',
	description	=>	'description',
	upload_id	=>	'upload_id',
	deleted		=>	'deleted',
	size		=>	'size',
	company_id	=>	'company_id',
	archive		=>	'archive',
);
%transforms = (
    filename => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);
%defaults = (
	deleted		=>	0,
	company_id	=>	undef,
	project_id	=>	undef,
	upload_id	=>	undef,
	size		=>	undef,
);

sub directory {
	my @path = split('/', $_[0]{filename} );
	pop @path;
	return join('/', @path );
}

sub size_text {
	return misc::format_bytes( $_[0]{size} );
} #end sub size_text

sub stat {
	if ( ! $_[0]{stat} ) {
		if ( $_[0]{archive} ) {
		$_[0]{stat} = [ stat $_[0]{archive}.$_[0]{filename} ];
		} else {
		$_[0]{stat} = [ stat $openprint::config{ProjectFilesPath}.$_[0]{filename} ];
		}
	}
	return $_[0]{stat};
}

sub created_on {
	if ( ! $_[0]{created_on} ) {
		my $stat = $_[0]->stat();
		if ( $stat and @{$stat} ) {
			my $mtime = $$stat[9];
			require DateTime;
			require DateTime::Format::Pg;
			my $DT = DateTime->from_epoch( epoch=>$mtime, time_zone=>$openprint::TZ );
			$_[0]{created_on} = DateTime::Format::Pg->format_datetime( $DT );
		} # end if
	} 
	return $_[0]{created_on};
}

1;
__END__
