package openprint::Complaint;
@ISA = qw( openprint::Object );
use strict;

use vars qw( $table $serial %fields %transforms %defaults );
$table = 'complaints';
$serial = 'compaints_id_seq';

%fields = (
	'company_id'	=>	'company_id',
	'company_name'	=>	'company_name',
	'user_id'		=>	'user_id',
	'contact_name'	=>	'contact_name',
	'created_on'	=>	'created_on',
	'ponum'			=>	'ponum',
	'docket'		=>	'docket',
	'howreceived'	=>	'howreceived',
	'description'	=>	'description',
	'comments'		=>	'comments',
);

1;
__END__
