use strict;
package openprint::Quote_Log;
our @ISA = qw(openprint::Object);

use vars qw( $table $serial %fields %transforms %defaults );

$table = 'quote_log';
$serial= 'quote_log_id_seq';
%fields = (
	id			=>	'id',
	quote_id	=>	'quote_id',
	company_id	=>	'company_id',
	user_id		=>	'user_id',
	created_on	=>	'created_on',
	description	=>	'description',
);
%transforms = (
);
%defaults = (
	created_on	=>	'NOW()',
);

sub description_html {
	my $desc = $_[0]{description};
	$desc =~ s/quote (\d+)/<a href="\/main\/quote\/history_details.html?quote_id=$1">quote $1<\/a>/;
	$desc =~ s/project (\d+)/<a href="\/main\/project\/view.html?ProjectIndex=$1">project $1<\/a>/;
	return $desc;
} # end sub description_html
1;
__END__
