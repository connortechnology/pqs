package logger;
require Encode;
require Date::Format;
use strict;

my %levels = (
	debug	=>	0,
	info	=>	1,
	warn	=>	2,
	error	=>	3,
);

use constant DEBUG	=>	0;
use constant INFO	=>	1;
use constant WARN	=>	2;
use constant ERROR	=>	3;

sub new {
	my $self = {};
    bless( $self, shift );
	my $opts = shift;
	if ( ref $opts eq 'HASH' ) {
		$$self{level} = $levels{$$opts{level}};
		$self->file( $$opts{file} );
	} elsif ( $opts ) {
		$self->{level} = $levels{$opts};
		$self->file();
	} # end if
	return $self;
} # end sub new

sub level {
	$_[0]{level} = $levels{$_[1]} if @_ > 1;
	return $levels{$_[0]{level}};
} # end sub level

sub file {
	my ( $self, $file ) = @_;
	$$self{file} = $file;
	return;
} # end sub file

sub print {
	my ( $self, $message ) = @_;
	$message = Encode::encode('utf-8',$message );
	
	if ( $$self{file} ) {
		my $fh = $$self{fh};
		#if ( ! $fh ) {
			if ( ! open( $fh, ">>$$self{file}" ) ) {
				print STDERR "Unable to open $$self{file}. : $!";
				print STDERR $message;
				return;
			} else {
				$| = 1;
				$$self{fh} = $fh;
			} # end if
		#} # end if

		print $fh Date::Format::time2str( '[%C] ', time ) . $message;
		close ( $fh );
	} else {
		print STDERR $message;
	} # end if
} # end sub print

sub hup {
	my ( $self ) = @_;
	if ( $$self{file} ) {
		close($$self{fh}) if $$self{fh};
		if ( ! open( $$self{fh}, ">>$$self{file}" ) ) {
			print STDERR "Unable to open $$self{file}. : $!";
		} else {
			$| = 1;
		} # end if
	} # end if
} # end sub hup

sub emerg {
	my $self = shift;
}

sub alert {
	$_[0]->print( "[alert] $_[1]\n" );
}
sub crit {
    my $self = shift;
	my $message = shift;
	$self->print( "[crit] $message\n" );
}
sub error {
	my ( $caller, undef, $line ) = caller;
	if ( $_[0]{level} <= ERROR ) {
		$_[0]->print( "[error] $caller:$line $_[1]\n" );
	} # end if
}
sub warn {
	if ( $_[0]{level} <= WARN ) {
		$_[0]->print( "[warn] $_[1]\n" );
	} # end if
}
sub notice {
    my $self = shift;
	my $message = shift;
	$self->print( "[notice] $message\n" );
}
sub info {
	if ( $_[0]{level} <= INFO ) {
		$_[0]->print( "[info] $_[1]\n" );
	} # end if
}
sub debug {
	my ( $caller, undef, $line ) = caller;
	if ( $_[0]{level} <= DEBUG ) {
		$_[0]->print( "[debug] $caller:$line $_[1]\n" );
	} # end if
}

1;
__END__
