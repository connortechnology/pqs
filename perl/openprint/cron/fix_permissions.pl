#!/usr/bin/perl

my ( $skin_path, $owner, $group ) = @ARGV;

my @directory = opendir $skin_path;
foreach my $filename ( @directory ) {
	next if $filename =~ /^\./; # This will pass over hidden files as well then

	
} # end foreach file
