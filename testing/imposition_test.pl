#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Add the perl directory to @INC
use lib '/home/runner/work/pqs/pqs/perl';

# Test that the imposition module can be loaded
use_ok('PQS::Imposition');
use_ok('PQS::Imposition::Node');
use_ok('PQS::Imposition::Constants');

# Basic test to ensure module loads
ok(1, 'Modules loaded successfully');

done_testing();
