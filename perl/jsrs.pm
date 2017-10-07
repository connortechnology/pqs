package jsrs;
use strict;
use warnings;

use base qw( Exporter );

our @EXPORT_OK = qw(encode_pairs encode_array);
our @EXPORT    = qw(MODIFY_CODE_ATTRIBUTES);    # Attribute handler.

use Apache2::Const qw(:common);
use Apache2::Log       ();
use Petal             ();
use Symbol            qw(qualify_to_ref);
use JSON::XS 2.0      qw(encode_json);
use session;

use PQS::DB ();
use PQS::Constants;
require misc;
require eprint::login;

# Template locations.
use constant JSRS_FILE  => 'jsrs.htm';       # Standard template.
use constant JSRS_ERROR => 'jsrs_error.htm'; # User error template.
use constant JSRS_DEBUG => 'jsrs_debug.htm'; # Developer debugging template.

# Package variable for storing functions we're allowed to execute from a web
# request. Populated by the attribute handler.
our @allowed_functions = ();

# Attribute handler for :JSRS. It adds the code reference to the allowed
# execution codes.
sub MODIFY_CODE_ATTRIBUTES {
    my ($pkg, $code, @attrs) = @_;

    my @unknown_attrs = grep { $_ ne 'JSRS' } @attrs;

    # If our attribute was found, the function may be called from the web.
    if (@unknown_attrs != @attrs) { push @allowed_functions, $code; }

    # Unknown attributes are passed on.
    return @unknown_attrs;
}

sub handler {
    my ($r) = @_;
    $r  = Apache2::Request->new( $r );

    my $variable   = {};
    my $start_time = time;

    my $dbh = PQS::DB->connect($r);
    $dbh->do(q{SET TRANSACTION READ ONLY});

    session::r($r);
    session::log($r->log);
    session::dbh($dbh);

    # If you don't have a cookies, too bad.
    my $cookie = misc::get_cookie();

    return FORBIDDEN if !defined $cookie || $cookie eq '';

    # If the customer isn't valid and logged in, they can't use us.
    my $cust_id = eprint::login::get_login_info(
        $r->log, $dbh, $cookie, $variable, 'C'
    );

    # Check to see if we are logged in to any section.
    $cust_id = $dbh->selectrow_array(q{
        SELECT lngcustomerid FROM tbl_logged_in 
        WHERE strsessionid = ? AND lngcustomerid <> 0
    }, undef, $cookie) unless $cust_id;

    return FORBIDDEN unless $cust_id;

    my $status = jsrs::dispatch($r, $dbh, $variable);

    $dbh->rollback;
    $dbh->disconnect;

    return $status;
}

# Call the function/method asked for by the user and send the formatted HTML
# return to the user's browser.
sub dispatch {
    my ($r, $dbh, $variable) = @_;

    my $retval = eval {
        my ($obj, $func, $args) = build_function_call($r);

        # NOTE: Do _NOT_ change &$f syntax to $f->() as a 'pertubable' (to
        # quote MJD) error in Memoize/Perl's magic goto may occur resulting in
        # a "Anonymous function called in forbidden scalar context;" error.

        # Dispatch the request. OO methods get themselves as the first
        # argument. Then the "standard" four, plus the user form supplied.
        return &$func(
            ($obj ? $obj : ()), $r, $r->log, $dbh, $variable, @$args
        );

    };

    unless ($@) {
        $variable->{payload} = encode_json($retval);
        $variable->{C}       = $r->param('C');
        return send_payload( $r, DONE, JSRS_FILE, $variable );
    }
    else { # Error
        if (DEBUG) { return jsrs_debug(   $r, $variable, $@ ); } # Devel.
        else       { return return_error( $r, $variable, $@ ); } # User
    }

    return SERVER_ERROR;
}

# Using the form submitted by the user, process that into a usable function
# reference and arguement list. Security checks to see if the function is
# allowed occur here as well.
sub build_function_call {
    my ($r)  = @_;
    my $func = $r->param('F');

    die "No function provided.\n" unless $func;

    # Determine the function's package and namespace.
    my ($package, $name) = $func =~ /^(.+)::([^:]+)$/;

    # Load the package (if it's valid and compiles).
    die "$func is not a valid function.\n" unless $package && $name;

    # We might want to look into this in the future to ensure that there's no
    # evil code in a BEGIN {} block of any packages available on the system,
    # as require() will run it even just like this.
    eval "require $package;";

    die "Failed requiring $package. Reason: $@\n" if $@;

    # If the package is an OO class see if can perform the named method,
    # otherwise get the code ref out of the package's symbol table.
    my $obj = $package->can('new') ? $package->new : undef;
    my $ref = $obj ? $package->can($name)
                   : *{qualify_to_ref($name, $package)}{CODE};

    # Check that the variables exists as a function.
    die "$func is not a defined function." unless defined $ref && $ref;

    # Generate the functions argument list from the parameters JSRS passes.
    # (In its weird format).
    my @args = map  { $_ = $r->param($_->[1]);          # Value of field
                      $_ = substr($_, 1, length($_)-2); # Remove wrapping []
                      s/\'/\\\'/g;                      # 'un-escape'
                      /(null|undefined)/ ? undef : $_;  # JS special values
                    }
               sort { $a->[0] <=> $b->[0]  } # Sort numerically by field id.
               map  { /(\d+)$/; [ $1, $_ ] }
               grep { /^P\d+/              } # Pn is a 'Parameter' field.
                    $r->param;

    return ($obj, $ref, \@args);
}

# Process the given template with the supplied data and return it to the user
# with the HTTP status code given in $retval.
sub send_payload {
    my ($r, $retval, $file, $data) = @_;

    my $template = Petal->new(
        base_dir => $r->document_root,
        file     => $file,
        input    => 'HTML',
        output   => 'HTML',
    );

    $r->status($retval) if $retval != DONE && $retval != DECLINED;

    $r->content_type('text/html');

    print $template->process(%$data);

    return DONE;
}

# Return a full formatted stack trace of the trapped error.
sub jsrs_debug {
    my ($r, $variable, $error) = @_;

    require Error::StackTrace;
    my $stack_trace = Error::StackTrace::trace($r, $error);

    return send_payload(
        $r, SERVER_ERROR, JSRS_DEBUG,
        { C => $r->param('C'), error => $stack_trace }
    );
}

# Users get pretty error messages when the server dies.
sub return_error {
    my ($r, $variable, $error) = @_;

    my $rip_out = sprintf qr/ at %s line %d.\n*$/, (caller())[1, 2];

    $error      =~ s/$rip_out//;
    $error    ||= 'Unknown error occurred!';

    return send_payload(
        $r, SERVER_ERROR, JSRS_ERROR, {
            %{$variable},
            error => $error,
            C     => $r->param('C'),
        }
    );
}


# The returned payload (embedded in a textarea) is serialised in an odd
# format with a pipe (|) between each key/value pair and a tilde (~) between
# the key and value.
sub encode_pairs {
    my @input_array = @_;

    no warnings qw(uninitialized);

    my $name = q{};

    # If the input is uneven we assume we're dealing with a set of named
    # pairs (some weird format cooked up for an unknown reason long ago).
    if (@input_array % 2 == 1) {
        $name = shift @input_array;
        $name = "$name~";
    }

    my @results;

    # Serialise each pair in turn.
    for ( my $n = 0; $n < @input_array; $n += 2) {
        push @results, $name . join q{~}, @input_array[$n, $n + 1];
    }

    # Join the pairs into a serialised structure.
    return join q{|}, @results;
}

# DEPRECATED. Originally used for named hash sets, now handled by
# encode_pairs.
sub encode_array { return encode_pairs(@_); }

1;
