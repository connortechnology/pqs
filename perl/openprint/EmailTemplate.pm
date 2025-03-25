package openprint::EmailTemplate;
@ISA = qw(openprint::Object);

use strict;
use vars qw( $debug $table $serial %fields %defaults %transforms );

$debug = 0;
$table = 'EmailTemplates';
$serial = 'emailtemplates_id_seq';

%fields = (
	'id'				=>	'id',
	'name'				=>	'name',
	'body'				=> 'body',
	'created_on'		=> 'created_on',
	'updated_on'		=> 'updated_on',
	'deleted'			=> 'deleted',
);

%transforms = (
);
%defaults = (
	'created_on'	=> q`'NOW()'`,
	'updated_on'	=> q`'NOW()'`,
	'deleted'		=> 0,
);

1;
__END__
