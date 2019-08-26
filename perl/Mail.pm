package Mail;
use Encode;
use MIME::QuotedPrint;

sub encode_qp {
	my $text = shift;

	$text = encode("UTF-8", $text);

	$text = MIME::QuotedPrint::encode_qp($text);

	return $text;
}
1;

__END__

