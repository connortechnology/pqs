=head1 NAME

Error::StackTrace - Pretty HTML stack traces (with optional error message).

=head1 SYNOPSIS

  use Error::StackTrace;

  # The error message is optional.
  my $html = trace($r, $err);

=head1 DESCRIPTION

Returns an valid XHTML document containing a stack trace and dump of all
arguments to the functions in the frame when called. Currently only runs under
mod_perl with seperate support files (Petal template and CSS).

=head1 TODO
=over
=item
Dump the environment.
=item
Under mod_perl we should dump the Apache object.
=item
Eliminate the need to be run under mod_perl, though add awareness of it for
special features.
=item
Use Petal to call the stack frames directly instead of loading it all into an
array of hashes.
=cut
package Error::StackTrace;

use strict;
use warnings;

use Apache2::Const qw(:common);
use Data::Dumper qw(Dumper);
use Devel::StackTrace ();
use Petal ();

use base qw(Exporter);
our @EXPORT  = qw(trace);
our $VERSION = '$Revision: 1.3.24.1 $';

sub trace {
    my ($r, $err) = @_;
print STDERR "HAVE STACK TRACE HERE  \n";

    local $Data::Dumper::Terse = 1; # Don't append 'VARn' to dumper output.

    my $trace = ref $err && ref $err eq 'PQS::Error'
        ? $err->trace
        : Devel::StackTrace->new(
            ignore_package => [ qw(Devel::StackTrace), __PACKAGE__ ]);

    # Discard the 'starting' frame as it's just startup under mod_perl.
    $trace->prev_frame; # if MOD_PERL;

    my @stack;
    my @ministack;
	my $cnt;
    while (my $frame = $trace->prev_frame) {
        next if $frame->subroutine eq 'Apache2::StatINC::__ANON__';
		$cnt++;
print STDERR "HAVE COUNT: $cnt  - " . $frame->subroutine .' '.$frame->filename.':' . $frame->line."\n";

        my ($pkg, $func) = $frame->subroutine =~ /^(.*?)::(\w+)$/;
        
        # Eval blocks.
        $func = '(eval)' if $frame->subroutine eq '(eval)';

        push @ministack, {
            filename => $frame->filename,
            line     => $frame->line,
            caller   => $frame->package,
		};
        
        push @stack, {
            filename => $frame->filename,
            line     => $frame->line,
            caller   => $frame->package,
            called   => $pkg,
            function => $func,
            context  => $frame->wantarray ? 'list' : 'scalar',
            args     => [ map { { 
                type     => ref $_ ? ref $_ : 'VALUE', 
                value    => Dumper($_),
                original => $_,
            } } $frame->args ],
        };
    }

    # If we're in the stack, remove us and and the call to us.
    pop @stack and pop @stack;

    #print STDERR "HAVE ERROR STACK ", Dumper($err->message);

    # Output the template.  
    my $t = Petal->new(
		base_dir => $r->document_root,
    #base_dir =>  '/usr/local/share/pqs/www', 
        file     => '/error/debug.html'
    );

    return $t->process(
        error => $err,
        stack => \@stack, 
    );
}

1;
