use strict;
package openprint::PaperRecommendation;
our @ISA = qw(openprint::Object);

use openprint ();
use vars qw($debug %session $dbh $log $table $serial %fields %find_fields %transforms %defaults @identified_by);
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*session = \%openprint::session;

require openprint::Paper;
require openprint::ProjectType;

$debug = 0;

$table = 'tbl_paper_recommendations';
$serial = 'tbl_paper_recommendations_id_seq';
#@identified_by = ('paper_id','projecttype_id');

%fields = (
  id				=>	'id',
	paper_id		=>	'lngpaperindex',
	projecttype_id		=>	'lngprojecttypeindex',
  presstype_id      =>  'lngpresstype',
  visible => 'ysnvisible',
);
%find_fields = (
);

%transforms = (
  id			=>	[ 's/\D//g', '<2147483647' ],
	paper_id			=>	[ 's/\D//g', '<2147483647' ],
	projecttype_id			=>	[ 's/\D//g', '<2147483647' ],
);

%defaults = (
  visible=>q`'Y'`,
);

sub Paper {
	return new openprint::Paper( $_[0]{paper_id} );
} # end sub Paper
sub Stock {
	return new openprint::Paper( $_[0]{paper_id} );
} # end sub Paper

sub ProjectType {
  require openprint::ProjectType;
	return openprint::ProjectType->find( id=>$_[0]{projecttype_id} );
} # end sub ProjectType

sub presstype {
  my %press_types = @{$dbh->selectall_arrayref(q{
  SELECT e.lngindex AS id, strname AS name
  FROM equipment_type_service_type t, tbl_equipment_type e
  WHERE t.equipment_type = e.lngindex AND t.service_type=?
  ORDER BY 2
  }, { Slice => {} }, 68)}; # Printing

  return $press_types{$_[0]{presstype_id}};
}

1;
__END__
