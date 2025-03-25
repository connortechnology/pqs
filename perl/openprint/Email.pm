use strict;

package openprint::Email;
our @ISA = qw( openprint::Object );

use openprint ();
require email;
require ssi;
require MIME::QuotedPrint;
require MIME::Base64;
require Encode;
require File::Slurp;

use vars qw( $debug $table $serial %fields %transforms %defaults );
$debug = 0;

%fields = (
		from	=>	'from',
		subject	=>	'subject',
		ATTACHMENTS	=>	'ATTACHMENTS',
		'Reply-To'	=>	'Reply-To',
		);

sub html_body {
	my ( $self, $html ) = @_;
	$$self{HTML_BODY} = $html;
} # end sub html_body

# The idea is that the params don't modify the object.
sub send {
  require Mail::Sendmail;
	my ( $self, %params ) = @_;
	if ( $debug ) {
		$openprint::log->debug("Sending an email");
		foreach my $k ( keys %params ) {
			$openprint::log->debug("Params: $k => $params{$k}");
		} # end 
	} # end if

	my $results;
	if ( $params{FROM} ) {
		$$self{from} = $params{FROM};
	} # end if
	if ( $params{'Reply-To'} ) {
		$$self{'Reply-To'} = $params{'Reply-To'};
	} # end if

	my @bcc;
	if ( $params{BCC} ) {
		foreach my $bcc ( ref $params{BCC} eq 'ARRAY' ? @{$params{BCC}} : $params{BCC} ) {
			if ( ref $bcc eq 'openprint::User' ) {
				push @bcc, sprintf('"%s" <%s>', $bcc->name(), $bcc->email() );
			} else {
				push @bcc, $bcc;
			} # end if
		} # end foreach bcc
	} # end if

	my %mail = (
			'content-type'	=>	$$self{'content-type'},
			BOUNDARY =>	$$self{boundary} ? $$self{boundary} : '====' . time() . '====',
			( $params{CC} ? ( CC		=>	$params{CC} ) : () ),
			( @bcc ? ( BCC		=>	join(',', @bcc ) ) : () ),
			Smtp    => ($params{SMTP} ? $params{SMTP} : $openprint::config{smtp_server}),
			( $params{'Return-receipt-to'} ? ( 'Return-receipt-to' => $params{'Return-receipt-to'} ) : () ),
			( $params{'Disposition-Notification-To'} ? ( 'Disposition-Notification-To' => $params{'Disposition-Notification-To'} ) : () ),
			FROM    => ( ref $$self{from} eq 'openprint::User' ? sprintf('"%s" <%s>', $$self{from}->get('name','email') ) : $$self{from} ),
			( $$self{'Reply-To'} ? ( 'Reply-To'    => ( ref $$self{'Reply-To'} eq 'openprint::User' ? sprintf('"%s" <%s>', $$self{'Reply-To'}->get('name','email') ) : $$self{'Reply-To'} ) ) : () ),
			SUBJECT => ( $params{SUBJECT} ? $params{SUBJECT} : $$self{subject} ),
			BODY	=>	( exists $params{BODY} ? $params{BODY} : $$self{body} ),
			);
#$log->debug("SMTP: $mail{SMTP}, from: $mail{from} subject: $mail{SUBJECT}");
	my @attachments = $params{ATTACHMENTS} ? @{$params{ATTACHMENTS}} : ();
	push @attachments, ( $$self{ATTACHMENTS} ? @{$$self{ATTACHMENTS}} : () );

	if ( @attachments or $params{HTML_BODY} or $$self{HTML_BODY} ) {
		$mail{BOUNDARY} = '====' . time() . '====' if ! $mail{BOUNDARY};
		my $message = $mail{BODY};

		$mail{'MIME-Version'} = '1.0';
		$mail{BODY} = "\nThis is a message with multiple parts in MIME format.\n";

# start with the current body
		if ( $message ) {
			$mail{BODY} .= "--$mail{BOUNDARY}\n";
			$mail{BODY} .= 'Content-Type: ' . ($mail{'content-type'} ? $mail{'content-type'} : 'text/plain' ). '; charset="utf-8"; format="fixed"'."\n";
			$mail{BODY} .= "Content-Transfer-Encoding: quoted-printable\n";
			$mail{BODY} .= "\n".MIME::QuotedPrint::encode_qp( Encode::encode('utf-8', $message ) ) . "\n";
		}

		if ( @attachments ) {
			$mail{'content-type'} = "multipart/mixed;\n  boundary=\"$mail{BOUNDARY}\"\n";
		} else {
			$mail{'content-type'} = "multipart/alternative;\n  boundary=\"$mail{BOUNDARY}\"\n";
		}

		if ( $params{HTML_BODY} ) {
			$mail{BODY} .= "--$mail{BOUNDARY}\nContent-Type: text/html; charset=\"utf-8\";\n";
			$mail{BODY} .= "Content-Transfer-Encoding: quoted-printable\n";
			$mail{BODY} .= "\n".MIME::QuotedPrint::encode_qp( Encode::encode('utf-8',$params{HTML_BODY}) ) . "\n";
		} elsif ( $$self{HTML_BODY} ) {
			$mail{BODY} .= "--$mail{BOUNDARY}\nContent-Type: text/html; charset=\"utf-8\";\n";
			$mail{BODY} .= "Content-Transfer-Encoding: quoted-printable\n";
			$mail{BODY} .= "\n".MIME::QuotedPrint::encode_qp( Encode::encode('utf-8',$$self{HTML_BODY}) ) . "\n";
		} else {
			my ( $name, $text, $type, $encoding ) = splice @attachments,0,4;
			$mail{BODY} .= "--$mail{BOUNDARY}\nContent-Type: $type;\n";
			$mail{BODY} .= "Content-Transfer-Encoding: $encoding\n";
			$mail{BODY} .= "\n$text\n";
		} # end if

		while ( @attachments ) {
			my ( $name, $text, $type, $encoding ) = splice ( @attachments,0,4 );
			$mail{BODY} .= "--$mail{BOUNDARY}\nContent-Type: $type;\n";
			$mail{BODY} .= "\tname=\"$name\"\n" if $name;
			$mail{BODY} .= "Content-Transfer-Encoding: $encoding\n";
			$mail{BODY} .= "Content-Disposition: attachment;\n";
			$mail{BODY} .= "\tfilename=\"$name\"\n" if $name;
			$mail{BODY} .= "\n$text\n";
		} # end while

# Signal end of attachments
		$mail{BODY} .= "--$mail{BOUNDARY}--\n\n";
		$openprint::log->debug($mail{BODY}) if $debug;
	} # end if attachments or HTML BODY

	my @recipients = $self->to();
#$openprint::log->debug("Email: Recipients @recipients");
	if ( $params{TO} ) {
		if ( ref $params{TO} eq 'ARRAY' ) {
			@recipients = @{$params{TO}};
		} elsif ( ! ref $params{TO} ) {
			@recipients = split( /,;\s/, $params{TO} );
		} else {
			@recipients = ( $params{TO} );
		} # end if
	} # end if
$openprint::log->debug("Email: Recipients @recipients");
	foreach my $recipient ( @recipients ) {
		next if ! $recipient;

		if ( ref $recipient eq 'openprint::User' ) {
			if ( $params{TO_EXCLUDE} and filter_exclude( $recipient, $params{TO_EXCLUDE} ) ) {
				$results .= 'Not sending to ' . $recipient . ' because they have been excluded.<br/>';
				next;
			} # end if

			my @to;
			foreach my $email ( split (/,;\s/,	$recipient->email() ) ) {
				s/^\s+//, s/\s+$// for $email;
#$openprint::log->debug("Email: checking vacation for $email");
				if ( my $vacation = email::get_vacation_entry( $email ) ) {
					if ( ! $$vacation{system_emails} ) {
						$results .= 'Not sending to ' . $email . ' because they are on vacation.<br/>';
#$openprint::log->debug("Email: got vacation for $email");
						next;
					}
				} # end if
				push @to, sprintf('"%s" <%s>', $recipient->name(), $email );
			} # end foreach email
			next if ! @to;
			$mail{TO} = join(',', @to );
		} else {
			s/^\s+//, s/\s+$// for $recipient;
			if ( $recipient =~ /^"(.*)" <(.*)>$/ ) {
				my ( $name, $email ) = ( $1, $2 );

				if ( $params{TO_EXCLUDE} and filter_exclude( $email, $params{TO_EXCLUDE} ) ) {
					$results .= 'Not sending to ' . $email . ' because they have been excluded.<br/>';
					next;
				} # end if

				if ( my $vacation = email::get_vacation_entry( $email ) ) {
					if ( ! $$vacation{system_emails} ) {
						$results .= 'Not sending to ' . $email . ' because they are on vacation.<br/>';
						next;
					}
				} # end if
				$mail{TO} = $recipient;
			} else {
				if ( $params{TO_EXCLUDE} and filter_exclude( $recipient, $params{TO_EXCLUDE} ) ) {
					$results .= 'Not sending to ' . $recipient . ' because they have been excluded.<br/>';
					next;
				} # end if
				if ( my $vacation = email::get_vacation_entry( $recipient ) ) {
					if ( ! $$vacation{system_emails} ) {
						$results .= 'Not sending to ' . $recipient . ' because they are on vacation.<br/>';
						next;
					}
				} # end if
				$mail{TO} = $recipient;
			} # end if
		} # end if

		if ( $openprint::config{EmailTo} ) {
			$mail{TO} = $openprint::config{EmailTo};
      delete($mail{BCC});
      delete($mail{CC});
		} # end if
		if ( $openprint::config{EmailBCC} ) {
      $mail{BCC} = $mail{BCC} ? $mail{BCC}.', '.$openprint::config{EmailBCC} : $openprint::config{EmailBCC};
		} # end if
		Mail::Sendmail::sendmail(%mail) || $openprint::log->error( "Error: $Mail::Sendmail::error\n" );
		$results .= 'Sent to: ' .  ssi::htmlize( $mail{TO} ) . '<br/>';

	} # end foreach recipient
	return $results;

} # end sub send

sub filter_exclude {
	my ( $email, $exclude ) = @_;
	$email = $email->email() if ref $email eq 'openprint::User';

	if ( ref $exclude eq 'ARRAY' ) {
		if ( ref $$exclude[0] eq 'openprint::User' ) {
			return 1 if sets::isin( $email, [ map { $_->email() } @{$exclude} ] );
		} else {
			return 1 if sets::isin( $email, $exclude );
		} # end if
	} elsif ( ref $exclude eq 'openprint::User' ) {
		return 1 if $email eq $exclude->email();
	} # end if
	return 0;
}

sub delete {

#sql::execute( undef, $dbh, 'DELETE FROM mailbox WHERE username=?', $_[0]{id} );
} # end sub delete

sub to {
	return ();
} # end sub to

sub attachments {
	if ( @_ > 1 ) {
		$_[0]{ATTACHMENTS} = $_[1];
	}
	if ( ! $_[0]{ATTACHMENTS} ) {
		$_[0]{ATTACHMENTS} = [];
	}
	return @{$_[0]{ATTACHMENTS}};
}

sub add_pdf_attachment_from_html {
	my ( $self, $name, $html ) = @_;

	my @attachments;
  #$html = Encode::encode('utf-8', $html);

  if ( open my $fh, ">:utf8", '/tmp/'.$name.'.html' ) {
    print {$fh} $html;
    close $fh;
	#if ( File::Slurp::write_file('/tmp/'.$name.'.html', { atomic => 1, err_mode=>'carp', binmode => ':raw' }, \$html ) ) {
		`wkhtmltopdf --encoding utf-8 -q "/tmp/$name.html" "/tmp/$name.pdf"`;
		my $pdf = File::Slurp::read_file( "/tmp/$name.pdf", err_mode => 'carp' );
    #unlink "/tmp/$name.html";
		unlink "/tmp/$name.pdf";
		if ( $pdf ) {
			push @attachments, ($name.'.pdf', MIME::Base64::encode_base64($pdf), 'application/octet-stream', 'base64');
		} else {
			$openprint::log->debug("Error making pdf");
		} # end if has pdf contents
	} # end if successfully wrote html content
	my $results;
	if ( ! @attachments ) {
		$results .= 'Unable to make a pdf.  Using HTML version.<br/>';
		push @attachments, ($name.'.html', MIME::QuotedPrint::encode_qp($html), 'text/html', 'quoted-printable');
	} # end if
	$$self{ATTACHMENTS} = [] if ! $$self{ATTACHMENTS};
	push @{$$self{ATTACHMENTS}}, @attachments;
	return $results;
}

sub add_html_attachment {
	my ( $self, $name, $html ) = @_;
	push @{$$self{ATTACHMENTS}}, ($name, MIME::QuotedPrint::encode_qp(Encode::encode('utf-8',$html)), 'text/html', 'quoted-printable');
}
1;
__END__
