package eprint::Config;
use strict;
use warnings;
# Very simple INI parser that loads a fixed file during compile time and
# provides basic read only access to it. No sanitizing of inputs.


use constant CONFIG_FILE => 'printquotes.ini';

my $singleton;

# Returns the compile time loaded singleton.
sub new      { return $singleton } 
sub instance { return $singleton } 

# Simple INI style config parser, construct hash of hashes (key/val pair broken
# into sections).
sub _parse {
    my ($self, $filename) = @_;

    open(my $fh, $filename) or die "Couldn't open configuration file: $!";

    my $config = $self->{config} = {};
    my $section;

    while (<$fh>) {
        chomp;
        s/^\s*//;
        s/\s*$//;
        next unless /\S/;
        next if /^#/;

        if (/^ \[ (.*) \] $/x) {
            $section = $config->{$1} = {};
        }
        elsif (/^ (\w+) \s* = \s* (.*);?$/x) {
            die "Parse error: key=value pair outside of a section at ${filename}:$.." 
                unless $section;

            warn "Semi-colons don't terminate lines (${filename}:$.)" if /;$/;

            $section->{$1} = defined $2 && $2 eq '' ? undef : $2;
        }
        else {
            die "Parse error: Invalid line at ${filename}:$.";
        }

    }

    close $fh or die "Couldn't close configuration file: $!";

    return $self;    
}

# Check to see if a given section.key exists.
sub exists { 
    my ($class, $section, $key) = @_;

    $class = $singleton unless ref $class;

    return exists $class->{config}{ $section }{ $key }
}

# Get the value of the given section.key.
sub get {
    my ($class, $section, $key) = @_;

    $class = $singleton unless ref $class;

    unless (exists $class->{config}{ $section }{ $key }) {
      my ( $caller, undef, $line ) = caller;
        warn "Key ($key) doesn't exist in section ($section) from $caller:$line";
        return undef;
    }

    my $value = $class->{config}{ $section }{ $key };

    return $value;
}


# Load the configuration during compile time.
sub BEGIN {

    $singleton = bless {}, __PACKAGE__;

    my @locations = @INC; 

    # Check current dir and all of @INC for the config.
    my $path;
    for ('.', @locations) {
        next unless -e $_ . '/' . CONFIG_FILE;

        $path = $_;
        last;
    }

    die "Couldn't find configuration file." unless $path;

    $singleton->_parse($path . '/' . CONFIG_FILE)
}

1;
