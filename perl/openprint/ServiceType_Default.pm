use strict;
package openprint::ServiceType_Default;
our @ISA = qw(openprint::Object);

use vars qw( $debug $table $serial %fields %find_fields %transforms %defaults );

$debug = 0;

$table = 'tbl_service_defaults';
$serial = 'tbl_Service_Defaults_lngId_seq';

%fields = (
	id		      		=>	'lngindex',
	projecttype_id	=>	'projecttype_id',
	projecttype	  	=>	undef,
	servicetype_id	=>	'lngserviceindex',
	servicetype		  =>	undef,
	name			      =>	'strfieldname',
	value	      		=>	'strdefaultvalue',
);
%find_fields = (
	projecttype	=>	'(SELECT name FROM project_types WHERE project_types.id=projecttype_id)',
	servicetype	=>	'(SELECT name FROM service_types WHERE service_types.id=lngserviceindex)',
);

%transforms = (
	id				=>	[ 's/\D//g' ],
	servicetype_id	=>	[ 's/\D//g' ],
	projecttype_id	=>	[ 's/\D//g' ],
  name => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
  value => [ 's/^\s+//', 's/\s+$//', 's/\s\s+/ /g' ],
);

%defaults = (
	projecttype_id		=>	undef,
);

sub projecttype {
	if ( @_ > 1 ) {
		my $ProjectType = openprint::ProjectType->find_one('name lc'=> lc openprint::ProjectType->transform('name',$_[1]) );
		if ( $ProjectType ) {
			@{$_[0]}{'projecttype_id','projecttype'} = @$ProjectType{'id','name'};
		} else {
$openprint::log->error("Unknown projecttype");
		} # end if
	} elsif ( $_[0]{projecttype_id} and ! $_[0]{projecttype} ) {
		$_[0]{projecttype} = new openprint::ProjectType( $_[0]{projecttype_id} )->name();
	} # end if
	return $_[0]{projecttype};
} # end sub projecttype

sub servicetype {
	if ( @_ > 1 ) {
		my $ServiceType = openprint::ServiceType->find_one('name lc'=> lc openprint::ServiceType->transform('name',$_[1]) );
		if ( $ServiceType ) {
			@{$_[0]}{'servicetype_id','servicetype'} = @$ServiceType{'id','name'};
		} else {
$openprint::log->error("Unknown servicetype");
		} # end if
	} elsif ( $_[0]{servicetype_id} and ! $_[0]{servicetype} ) {
		$_[0]{servicetype} = new openprint::ServiceType( $_[0]{servicetype_id} )->name();
	} # end if
	return $_[0]{servicetype};
} # end sub servicetype

1;
__END__
