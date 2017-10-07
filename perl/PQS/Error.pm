=head1 NAME

PQS::Error - Simple error tracking through overriden CORE::die

=head1 SYNOPSIS

  use PQS:Error; # Overrides die handler

  if ($@) {
      print $@->message;

      my $trace = $@->message; # Devel::StackTrace object.
  }

=head1 DESCRIPTION

Simple error tracking (even through evals). Not an exception handler. Should
play nicely with other modules.

=cut
package PQS::Error;
use strict;
use warnings;

use Carp;
use Exporter;
use PQS::Constants qw(DEBUG);

use base qw(Exporter);
our @EXPORT = qw(die);

use overload '""' => \&message;

sub die (@); # Prototype matches CORE::die.

# Allow "use PQS::Error qw(die)" to be localised to current package.
sub import {
    my $package = shift;

    # Don't use stack tracing die handler if we're not debugging.
    return unless DEBUG;

    $package->export(qw(CORE::GLOBAL die)) unless @_;
    Exporter::import($package, @_);
}

sub die (@) {
    my $err = $_[0];

    require Devel::StackTrace; # Don't use() for mem. concerns

    CORE::die @_
        if ref $err && grep { ref $err ne $_ } qw(SCALAR ARRAY HASH);

    CORE::die bless({
        message => Carp::shortmess(@_),
        error   => \@_,
        trace   => Devel::StackTrace->new(
            ignore_class => [qw(Devel::StackTrace)]
        ),
    }, 'PQS::Error');
}

sub message { shift->{message} }
sub trace   { shift->{trace}   }


1;
