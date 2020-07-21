package misc;
require Exporter;

@ISA    = qw(Exporter);

@EXPORT = qw(
    load_file
    save_file
    get_cookie
    get_upload
    get_upload_fh
    export_csv
    export
    generate_cookie
    get_destination
    send_email_with_attached_files
    send_email_with_attachment
    build_city_prov_country
	email_with_template
);

use Data::Dumper;
use Time::Local;
use Apache2::Cookie;
use Apache2::Util;
use Apache2::Upload;
use Text::CSV_XS;

use MIME::QuotedPrint;
use Mail::Sendmail;
use session;

use strict;
use POSIX qw( ceil floor strftime );

# strftime()'s "pretty date" format.  (I use the term pretty date loosely.)
use constant PRETTY_DATE => '%A %B %d %Y %I:%M%P';

use List::Util qw();

our @months = qw(
    January February March
    April   May      June
    July    August   September
    October November December
);

our @days = qw( Monday Tuesday Wednesday Thursday Friday Saturday Sunday );

sub getMonth {
    return $months[$_[0] - 1];
}

sub get_cookie {
    my ( $r, $log, $dbh, $variable ) = @_;

    my %cookies = fetch Apache2::Cookie;
    my $cookie  = $cookies{SessionID};
    #my $cookie  = $cookies{configuration::get_value($log, $dbh,'sitename')};

    return ref $cookie ? $cookie->value() : undef;
}

sub generate_cookie {
    my ( $r, $log, $dbh ) = @_;

        my $cookie = Apache2::Cookie->new($r,
            -name    => 'SessionID',
            -value   => gen_session_id(),
            -path    => '/',
            -domain  => configuration::get_value($log,$dbh,'cookiedomain')
        );

        $cookie->bake($r);

        return $cookie->value();
}
	
sub email_with_template {
	my ( $r, $log, $dbh, $file, $header, $data ) = @_;
	
	my $t = misc::load_file($r,'/email/email_template.html');

	$data->{ReplacementText} = qq{<!--#include virtual="$file"-->};
	$data->{siteURL} = "http://" . $r->hostname;
	
	$t = ssi::variable_substitution($r, $log, $dbh, $t, $data);

	misc::send_email_with_attachment(
         $r, $log, $header, '', encode_qp($t), 'text/html', 'quoted-printable'
    );
}


sub send_email_with_attached_files {
    my ( $r, $log, $mail, @attachments ) = @_;

    for ( my $index = 4; $index < scalar @attachments; $index += 4 ) {
        open ( F, $attachments[$index+1] )
            || $log->error("Can't open " . $attachments[$index + 1]);

        binmode F;

        $attachments[$index + 1] = join(
            qq{\r\n}, map { tr/\r\n//d; $_ } <F>
        );
		$mail->{BODY} = '';

        close F;
    }

    send_email_with_attachment( $log, $mail, @attachments );
}


# we should really be using mime-tools.
sub send_email_with_attachment {
    my ($r, $log, $mail, @attachments) = @_;
print STDERR "SEND EMAIL WITH ATTACHMENT START \n", Dumper($mail);
	
	my $list;
	map { $list->{$_} = 1 } split ',', $mail->{TO} || $mail->{To};

	$mail->{TO} = join ',', keys %{$list};

print STDERR "SEND MAIL TO: $mail->{TO} FROM $mail->{FROM} SUBJECT: $mail->{SUBJECT} $mail->{subject} \n";

	
    my $message = $mail->{BODY};

    my $boundary = "====" . time() . "====";

    $mail->{'content-type'}
        = "multipart/mixed;\r\n  boundary=\"$boundary\"\r\n";

    $boundary = '--'.$boundary;

    # start with the current body
    $mail->{'BODY'} .= "This is a multi-part message in MIME format.\n\n";

    if ( $message ) {
        $mail->{BODY} .= "$boundary\n"
                      .  "Content-Type: text/plain;\n"
                      .  "\tcharset=\"iso-8859-1\"\n"
                      .  "Content-Transfer-Encoding: 8-bit\n\n"
                      .  "\n$message\n";
    }
    else {
        my ($name, $text, $type, $encoding) = splice @attachments, 0, 4;

        $mail->{BODY} .= "$boundary\nContent-Type: $type;\n"
                       . "Content-Transfer-Encoding: $encoding\n\n"
                       . "$text\n";
    }

    my $attachmentname = '';
    while ( @attachments ) {
        my ($name, $text, $type, $encoding) = splice @attachments, 0, 4;
print STDERR "EMAIL DUMPER", Dumper($name );

        $mail->{BODY} .= "$boundary\nContent-Type: $type;\n"
                      .  ($name ? "\tname=\"$name\"\n" : q{})
                      .  "Content-Transfer-Encoding: $encoding\n"
                      .  "Content-Disposition: attachment;\n"
                      .  ($name ? "\tfilename=\"$name\"\n" : q{})
                      .  "\n$text\n";
        $attachmentname .= $name . ", ";
    }

    # Signal end of attachments
    $mail->{BODY} .= "$boundary--\n\n";
    insert_to_emaildb($mail, $attachmentname);
    sendmail( %$mail ) || $log->debug( "Error: $Mail::Sendmail::error\n" );
}

sub insert_to_emaildb {
    my $mail = shift;
    my $attachmentname = shift;
    my $dbh = session::dbh;

    my @k = keys $mail;
    my $subject;

    foreach my $key (@k){
        if ($key =~ /(subject)/i){
            $subject = $mail->{$key};
        }
    }

	eval {
		$dbh->  do("INSERT INTO public.tbl_email(from_address, to_address, subject, attachmentname)
		VALUES (?, ?, ?, ?)" , undef, $mail->{FROM}, $mail->{TO}, $subject, $attachmentname);
	}
    print STDERR "$mail->{FROM}, $mail->{TO}, $subject EMAIL HISTORY SAVED IN TBL_EMAIL DATABASE \n";
    
}


# We now use the SSI insert_html (which really just slurps in a file) as it
# respects site_specific directory changes and overrides.
sub load_file { ssi::insert_html(@_); }

sub gen_session_id {
    my @vals = ('0' .. '9', 'a' .. 'z', 'A' .. 'Z');
    my $string = '';

    for (1 .. 8) {
        $string .= $vals[int(rand scalar(@vals))];
    }

    return $string;
}

sub build_city_prov_country {
    return join q{, }, grep { $_ } @_;
}

sub gettime {
    my ($checktime) = @_;

    my @array;

    if (defined $checktime) {
        @array = reverse $checktime =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/;
        $array[4]--;
    }
    else {
        @array = localtime(time);
    }

    return timelocal(@array);
}

sub get_upload_fh {
    my ($r, $source) = @_;

    if (!defined $r->upload($source)) {
        $r->log_error("Failed fetching upload: $source");
        return;
    }

    return $r->upload($source)->fh;
}

#this should never ever ever ever be used. ever.
sub get_upload {
    my ( $r, $log, $source ) = @_;

    my $upload = $r->upload( $source );

    if ( !$upload ) {
        $log->error( "Failed to upload $source. " );
        return ();
    }

    my $fh = $upload->fh;

    my @buffer = <$fh>;

    return @buffer;
}
# by the way, did I mention ever?

sub save_file {
    my ( $log, $filename, @data ) = @_;

    if (!open( WFD, '>', $filename )) {
        $log->error("Failed opening file: $filename Reason: $!");
        return 0;
    }

    print WFD join qw{}, @data;

    if (!close WFD) {
        unlink $filename;
        $log->error( "Something wrong with the file, deleting it." );
        return 0;
    }

    return 1;
}

sub export_csv {
    return @_ == 4 ? new_export_csv(@_)
                   : old_export_csv(@_);
}

sub new_export_csv {
    my ($r, $variable, $filename, $data) = @_;

    my $csv = Text::CSV_XS->new({ eol => "\n" });

    my @output;

    foreach my $line (@{ $data }) {
        $csv->combine(@{ $line });
        push(@output, $csv->string());
    }

    export($r, undef, $variable, $filename, \@output);
}

sub old_export_csv {
    my ($r, $log, $variable, $filename, $header, $data) = @_;

    # NOTE: For some reason they decided to pass data as a flat array ref
    # instead of embedded arrays. scalar @$headers is the only way to know
    # when to break the record apart.
    my @output;

    my $csv = Text::CSV_XS->new();

    my $columns = scalar @$header;
    $csv->combine( @$header ); # Create header line.
    push @output, $csv->string() . "\n";

    # Remove any existence of CR or LF from $data arrayref.
    @$data = map { tr/\r\n//d; $_ } @$data;

    # Page through each 'record' and create a CSV line.
    for (my $i = 0; $i < @$data; $i += $columns) {
        $csv->combine( @{ $data }[$i..$i + $columns -1] );
        push @output, $csv->string() . "\n";
    }

    export( $r, $log, $variable, $filename, \@output );
}

sub export {
    my ( $r, $log, $variable, $filename, $data ) = @_;
    $r->headers_out->{'Content-Disposition'} = qq{attachment; filename="$filename"};

    $r->content_type( qq{application/octet-stream; name="$filename"} );
#    $r->content_encoding( "binary" );

    $variable->{Download} = $filename;
    $variable->{File_Data} = $data;
}

sub get_destination {
    my ( $r, $log, $uri ) = @_;

    my $dest = $uri ? $uri : $r->uri;

    my $query_string = $r->method ne 'GET' 
        ? undef
        : Apache2::Util::escape_path(join(q{;}, map { "$_=" . $r->param($_) } $r->param()), $r->pool);

    return $query_string ? "$dest?$query_string" : $dest;
}

sub pretty_date {
    return strftime(PRETTY_DATE, @_);
}

sub sum {
    return List::Util::sum @_;
}

sub error {
    my ( $log, $dbh, $variable, $error, $details ) = @_;

    $log->debug("Error: $error");
    $log->debug("Details: $details");

    $variable->{error}    = $error;
    $variable->{details}  = $details;
    $variable->{Redirect} = configuration::get_value($log, $dbh, 'errorpage');
}

sub unescape {
    my ($decode) = @_;

    return undef if !defined $decode;

    $decode =~ tr/+/ /;
    $decode =~ s/%([0-9a-fA-F]{2})/pack('c', hex $1)/ge;
    return $decode;
}

sub escape {
    my ($encode) = @_;

    return undef if !defined $encode;

    $encode =~ s/([^a-zA-Z0-9_.-])/sprintf('%%%02X',ord $1)/eg;
    return $encode;
}

sub trim {
    # im not sure any of the code would care, but if we just map @_, then the
    # original array being passed in would be trim()ed.. probably not what
    # they want.
    my @trimming = @_;
    return map { s/^\s*([\w\-\/\.]*)\s*$/$1/; $_ } @trimming;
}

sub round_up {
    return ceil($_[0]);
}

sub round_down {
    return floor($_[0]);
}


sub nav_get_next {
    my ( $r, $log, $dbh, $index, $indexname, $tablename, $cond, $ddmFieldName ) = @_;

    $cond = $cond ? "AND $cond " : '';

    my $id = $dbh->selectrow_array(qq{
        SELECT $indexname 
        FROM $tablename 
        WHERE $ddmFieldName = ( SELECT MIN($ddmFieldName) 
                                FROM $tablename
                                WHERE $ddmFieldName  > ( SELECT $ddmFieldName 
                                                         FROM $tablename 
                                                         WHERE $indexname = '$index' )
                                $cond )
    });

    if (!$id) {
        $id = $dbh->selectrow_array(qq{
            SELECT $indexname 
            FROM $tablename WHERE $ddmFieldName = ( SELECT MIN($ddmFieldName) 
                                                    FROM $tablename 
                                                    WHERE 1=1 
                                                          $cond )
        });
    }

    return $id;
}

sub nav_get_previous {
    my ($r, $log, $dbh, $index, $indexname, $tablename, $cond, $ddmFieldName) = @_;

    $cond = $cond ? "AND $cond " : '';

    my $id = $dbh->selectrow_array(qq{
        SELECT $indexname 
        FROM $tablename 
        WHERE $ddmFieldName = ( SELECT MAX($ddmFieldName) 
                                FROM $tablename
                                WHERE $ddmFieldName  < ( SELECT $ddmFieldName 
                                                         FROM $tablename 
                                                         WHERE $indexname = '$index' )
                                $cond )
    });

    if (!$id) {
        $id = $dbh->selectrow_array(qq{
            SELECT $indexname 
            FROM $tablename WHERE $ddmFieldName = ( SELECT MAX($ddmFieldName) 
                                                    FROM $tablename 
                                                    WHERE 1=1 
                                                          $cond )
        });
    }

    return $id;
}

1;
