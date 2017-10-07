=head1 NAME

PQS::StyleSheet - Dynamically replace and caches customer specific stylesheets.

=head1 SYNOPSIS

As an apache handler:

  <Location site_specific/styles/>
      SetHandler     perl-script
      PerlHandler    PQS::StyleSheet
      PerlSendHeader On
  </Location>

To generate an site stylesheet internally:

  use PQS::StyleSheet;
  
  my $style = generate($template_file, \%template_colours, \%site_colours);

=head1 TODO
=over

=item

Pass the stylesheet text as a reference instead of a copy.

=item

Instead of generating, then opening, then sending. Just print the generated
content when generation is needed.

=back
=cut
package PQS::StyleSheet;
use strict;
use warnings;
use utf8;

use base qw(Exporter);
our @EXPORT_OK = qw(generate);

use Apache2::Const qw(:common HTTP_SERVICE_UNAVAILABLE);
use Apache2::RequestIO ();
use Apache2::Log ();
use Apache2::RequestUtil ();
use Apache2::Response ();
use Fcntl qw(:flock);
use session;

# Template control.
use constant STYLE_DIR => '/styles/';
use constant COLOURS   => 'colours.txt';

sub handler {
    my $r = shift;
    my $template;  # Template stylesheet.

    # Only process requests for Cascading Style Sheets.
    return NOT_FOUND unless $r->uri =~ /.css$/;

    session::r($r);
    session::log($r->log);

    # The path to support files (site_specific stuff may not be under docroot).
    my $path = $r->document_root.'/site_specific/';
    $path = $r->dir_config('site_specific') if -e $r->dir_config('site_specific').STYLE_DIR.COLOURS;
    $path = $r->dir_config('custom_skin')  if -e $r->dir_config('custom_skin').STYLE_DIR.COLOURS;

    # If it wasn't for the fact site_specific files could be stored outside
    # the document root, we could use $r->filename. As it is we need to
    # generate the path from the requested location.
    my $filename = $path.$r->uri;

    # When a request for a stylesheet is made, the template stylesheet will be
    # looked for with the same relative path after the stylesheet location as
    # defined in the Apache configuration.
    $template = $path.$r->uri; $template =~ s/\/styles\//\/base-css\//;

    
    #
    # COLOUR REPLACEMENT
    # 
    
    # Determine if we need to (re)generate the stylesheet.
    my $generate = 0;

    # We need to generate the stylesheet if it doesn't exist in the cache.
    if (not -e $filename) {
        $generate = 1;
    }
    # If it does exist in the cache, we need to see if we can serve it as is,
    # or if the support files have been modified after we cached this version.
    else {
        # Get the last modified dates for all the files in question. We don't
        # bother checking the template colour file as changing that is useless
        # without changing the template stylesheet.
        my ($mfilename, $mtemplate, $mcolours) = map { (stat($_))[9] }
                                $filename, $template, $path.STYLE_DIR.COLOURS;

        # Regenerate the stylesheet if either the template or the site
        # specific colours have been modified since the last generation.
        $generate = 1 if ($mtemplate > $mfilename) || ($mcolours > $mfilename);
    }

    # Generate the image and write it to disk if need be.
    if ($generate) {
        # If we can't find the template we can't generate a site stylesheet.
        # The most likely reason for this is an improper URI.
        return NOT_FOUND unless -e $template and -f _;

        # If the template colours file is missing though, we need to complain
        # in the log as it's a real problem.
        unless (-e $path.STYLE_DIR.COLOURS and -f _) {
            $r->log->error("Template colours (".$path.STYLE_DIR.COLOURS.") does not exist");
            return NOT_FOUND;
        }

        # Get the colours if they're not defined. TODO We could cache these
        # (though not in global as multiple sites with different colours can
        # use the same server).
        my %t_colours = %{ get_colours($path."/base-css/".COLOURS) };
        my %s_colours = %{ get_colours($path.STYLE_DIR.COLOURS) };

        # Open the template and slurp it into a scalar.
        my $template = get_template($template); 

        output_file($filename, generate($template, \%t_colours, \%s_colours))
    }
 
    
    #
    # SERVE REQUESTED FILE
    #
    
    # If we're generating this internally through a subprocess and we don't
    # want the output, we'll just return OK here.
    return OK if $ENV{internal};

    # Set the file size, modification time, etc. headers for the client.
    $r->content_type('text/css; charset=utf-8');
    $r->set_content_length( -s $filename);
    $r->set_last_modified( (stat($filename))[9] );
    
    # Any error at this point is likely a permissions issue.
     open(my $fh,"<",$filename) or return FORBIDDEN;

    # If the client is only requesting the header, we'll give them just that.
    return OK if $r->header_only;
    
    # Lock the file for shared access, if a lock can't be aquired tell the
    # client the resource isn't currently available.
     flock   $fh, LOCK_SH or return HTTP_SERVICE_UNAVAILABLE;
     binmode $fh;
     $r->sendfile($filename);   # Output the file.
     flock $fh, LOCK_UN; # Unlock and cleanup.
     close $fh;

    return OK;
}

# Given a template stylesheet, a template colours hashref, and a site colours
# hashref, dynamically replace the template colours with site ones and return
# the site stylesheet.
sub generate {
    my $stylesheet = shift; # The template stylesheet.
    my $template   = shift; # Template colours.
    my $site       = shift; # Site specific colours.

    # Some simple assertions.
    die "Empty template stylesheet"                         if not $template;

    # Help spot spelling errors or version changes.
    warn "Colour mismatch, colour files do not define the same keys"
        unless (join '', sort keys %$template) eq (join '', sort keys %$site);

    # Build a colour mapping table.
    my %colours;
    $colours{ $template->{$_} } = $site->{$_} for keys %$template;

    # If a site specific colour does not exist for the template colour,
    # promote the template colour to site specific by removing it from the
    # search and replace list.
    foreach my $c (keys %colours) {
        next if defined $colours{$c};
        delete $colours{$c};
    }

    # Define a search pattern.
    my $pattern = do {
        my $colours = join '|', keys %colours;
        qr/($colours)/;
    };

    # For parsing the CSS we could use a full grammar or a token parser to
    # replace the colours in a context sensitive manner. Instead we'll just
    # use a simple regular expression.
    $stylesheet =~ s/$pattern/$colours{$1}/sig;

    return $stylesheet;
}

# Retrieve the requested stylesheet template.
sub get_template {
    my $filename = shift; # The colour definition file.
    my %colours;

    open(my $fh,"<","$filename") or die "Could not open template ($filename): $!";
    flock $fh, LOCK_SH      or die "Could not lock template ($filename): $!";

    local $/ = undef;
    my $template = "";
    while (<$fh>) {
      $template = $_;
    }
    
    flock $fh, LOCK_UN;    
    close $fh;

    return $template;
}


# Retrieve the colours from the provided colour file.
sub get_colours {
    my $filename = shift; # The colour definition file.
    my %colours;

    open(my $fh,"<","$filename") or die "Could not open colours ($filename): $!";
    flock $fh, LOCK_SH      or die "Could not lock colours ($filename): $!";

    # Many colour records in the may be stored in the colour file. Use a
    # simple regex to grab the record.
    while ( <$fh> ) {
        next unless /^\s*(\w+)\s*:(.*)$/i;
        $colours{ lc($1) } = $2;
    }
    
    flock $fh, LOCK_UN;    
    close $fh;

    return \%colours;
}

# Given a filename and text data, write to the file.
sub output_file {
    my $filename = shift;
    my $data     = shift;

    open(my $fh,">",$filename) or die "Could not open stylesheet ($filename): $!";
    flock   $fh, LOCK_EX    or die "Could not lock stylesheet ($filename): $!";
    print $fh $data       or die "Could not write stylesheet ($filename): $!";
    flock   $fh, LOCK_UN;
    close $fh;

    return 1;
}

1;
