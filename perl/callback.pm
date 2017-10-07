package callback;
use strict;
use warnings;
use Data::Dumper;

my $CALLBACKS = {};

#load callbacks recursivly from a designated directory
#it is expected that every non-hidden file will be a perl file
#each file needs to have code in it to register the callback
sub load_callbacks {
  my ($dir) = @_;
  my $df;

  opendir($df, $dir);
  while (my $file = readdir($df)) {
    next if ($file =~ m/^\./);

    if (-d "$dir/$file") {
      load_callbacks("$dir/$file")
    }

    if (-f "$dir/$file") {
      do "$dir/$file" or die $!;
    }
  }
  closedir($df);
}

#add callback function to the array
#the name is an identifier for debugging if required I don't expect them to be unique
sub register {
  my ($callback, $name, $func) = @_;

  $CALLBACKS->{$callback} = [] unless $CALLBACKS->{$callback};
  $CALLBACKS->{$callback} = [@{$CALLBACKS->{$callback}}, {name => $name, func => $func}];
}

#invokes a call back running all of the functions
sub call {
  my $callback = shift @_;

  return unless $CALLBACKS->{$callback};

  my @functions = @{$CALLBACKS->{$callback}};
  foreach my $func (@functions) {
    $func->{'func'}->(@_);
  }
}
1;