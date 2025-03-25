use strict;
package openprint::ProjectType_Template;
our @ISA = qw(openprint::Object);
require openprint::Object;

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );

$debug = 0;

$table = 'projecttemplate';
$serial = 'projecttemplate_id_seq';

%fields = (
	id				=>	'id',
	projecttype_id	=>	'projecttype_id',
	type			=>	'type',
	name			=>	'name',
	description		=>	'description',
	finished_width	=>	'dblfinishedwidth',
	finished_height	=>	'dblfinishedheight',
	flat_width		=>	'dblflatwidth',
	flat_height		=>	'dblflatheight',
	message			=>	'message',
);

%find_fields = (
	projecttype		=>	'(SELECT name FROM project_types WHERE project_types.id=projecttype_id)',
);

%transforms = (
	id				=>	[ 's/\D//g' ],
	finished_width	=>	[ 's/[^\.\d]//g' ],
	finished_height	=>	[ 's/[^\.\d]//g' ],
	flat_width		=>	[ 's/[^\.\d]//g' ],
	flat_height		=>	[ 's/[^\.\d]//g' ],
	type => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	description => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	message => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
	name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

%defaults = (
	finished_width	=> undef,
	finished_height	=> undef,
	flat_width		=> undef,
	flat_height		=> undef,
	message			=> undef,
);

1;
__END__
