package eprint::impositionObject;
use strict;
use warnings;

use Carp;

sub new {
	my ($class, $press) = @_;

	my $self = {
        press             => $press,
        setup             => undef,
        run_style         => undef,
        grain_direction   => undef,
        rotate_sheet      => undef,
        rows              => undef, # \
        cols              => undef, # / Still needed for multi-page for now.
        image_width       => undef,
        image_height      => undef,
        image_orientation => undef,
        spread_rows       => undef, # -|
        spread_cols       => undef, #  |-- Created by convert_imposition()
        spreads           => undef, # -|
        stitch_size       => undef,
        cut_off           => undef,
        paper             => {},
        layout            => [],
        tree              => undef,
        colour_bar        => 0,
        grip              => 0,
        gutter            => 0,
    };

	bless $self, $class;

    return $self;
}

sub set {
    my ($self, @params) = @_;

    my @param_map = qw(
        setSetup
        setStyle
        setGrainDirection
        setRotateSheet
        setRows
        setCols
        setImageWidth
        setImageHeight
        setImageOrientation
        setPaper
        setLayout
        setTree
        setColourBar
        setGrip
        setGutter
    );

    my $current_param = 0;

    foreach my $code_ref ( @param_map ) {
        $self->$code_ref( $params[$current_param++] );
    }
}

sub DESTROY { };

sub AUTOLOAD {
    my ($self, @params) = @_;

#    use Data::Dumper;
#    die Dumper \@_;

    my $command = our $AUTOLOAD;
       $command =~ s/.+::(get|set)//;
    my $which   = $1;

    $command = lcfirst $command;

    $command =~ s/([A-Z])/'_' . lc $1/eg;

    if ($command eq 'style') {
        $command = 'run_style';
    }

    if ($which eq 'set' && exists $self->{$command}) {
        $self->{$command} = $params[0];
    }
    elsif (!exists $self->{$command}) {
        croak "Invalid command: " . __PACKAGE__ . "->$command\n";
    }

    return $self->{$command};
}

1;
