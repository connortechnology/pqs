# Apache/mod_perl initialisation.

use strict;
use warnings; # Disable for production
use utf8;
use bytes;

require crypto;
require misc;


#Loading these early so that can use server root relative
use Apache2::Request ();
use Apache2::Const qw(:common);

use Apache2::RequestRec ();
use Apache2::Connection ();
use APR::URI ();
#use Apache2::Const ();
use Apache2::Log ();
use Apache2::ServerUtil ();
use Apache2::RequestIO ();
#use Apache::Session::Postgres ();
use Apache2::Cookie ();
use Apache2::Upload ();
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

# The location of Perl modules for this client.
use lib '/var/www/pqs/perl';
use lib '/var/www/pqs/perl/API';

require eprint::Config;
require session;
require eprint::www;

# Prevent XS from thorwing error where Readonly is loaded.
#$Readonly::XS::MAGIC_COOKIE = "Do NOT use or require Readonly::XS unless you're me.";

#$SIG{__DIE__} = sub { what_happend(@_); };

#load callbacks
#use callback;
#callback::load_callbacks('/var/www/pqs/perl/callbacks');

sub what_happend {

	my $err = shift;
	my $r   = $session::r;
	my $x = ref $err;


	print STDERR "WHAT HAPPENED ERROR: $x - $err \n";

	# Iterator is/has been thowing errors for a long time.
	# Not sure why, but let it go for now.
	return if $x eq 'Iterator::X::Am_Now_Exhausted';

	print STDERR "WHAT HAPPENED - Time to do stuff \n";

	require Error::StackTrace;
	my $st = Error::StackTrace::trace($r, $err);

	# Add a few of the Important Enviromnent Variable to the top of the page.
	map { $st =  "$_ = $ENV{$_}<br>\n" . $st; } ('HTTP_REFERER', 'REQUEST_URI');

	# Add all of the ENV data to the end of the page.
	map { $st .= "$_ = $ENV{$_}<br>\n"; } sort(keys(%ENV));

	my $id = db_error($r, $st);
	$st = "ERROR DB ID: $id <br>\n" . $st;
	#	email_error($r, $st);
	#	print STDERR "Error: ", $st;
	print $st;
  die;
	return OK;

	#	Apache->push_handlers("PerlCleanupHandler", sub { return OK; });

}

sub db_error {
	my ($r, $err) = @_; 
	my $dbh = PQS::DB->connect($r);
	my $id = $dbh->selectrow_array(q{SELECT nextval('error_log_seq')});
	$dbh->do(q{ 
		INSERT INTO error_log ( id, err, edate ) VALUES (?, ?, NOW()) 
		}, undef, $id,$err);

	$dbh->commit;
	$dbh->disconnect();
	return $id;
}

sub email_error {
	my ($r, $err) = @_;

	use MIME::QuotedPrint;

	my $msg = encode_qp($err);

	my @body = ('', $msg, 'text/html', 'quoted-printable');

	my %mail = (
		SMTP    => '192.168.1.73',
		FROM    => 'safeway@print-quotes-software.com',
		TO      => 'safeway@print-quotes-software.com',
		SUBJECT => 'Website Error',
	);

	misc::send_email_with_attachment($r, $r->log, \%mail, @body);
}

1;
__END__
