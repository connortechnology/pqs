#!/usr/bin/perl -w
use strict;

use LWP::UserAgent;
use HTTP::Request::Common;

# Popular currencies are: USD, GBP, EUR, and JPY.
my ($amount,$cf,$ct) = @ARGV[0..2];

my $request = GET "http://finance.yahoo.com/d/quotes.csv?s=$cf$ct=X&f=l1&e=.csv";

#"http://www.oanda.com/converter/classic?value="
				  #. "$amount&exch=" . uc($cf) . "&expr=" . uc($ct);
#$request->proxy_authorization_basic('username','password');

my $ua = new LWP::UserAgent;
#(my $ua = (new LWP::UserAgent))->proxy('http','http://yourproxyhere.co
#+m:1080');
my $resp = $ua->request($request);

die $resp->status_line if ($resp->is_error());
$_ = $resp->{_content};
s/^.*<!-- conversion result starts//s;
s/<!-- conversion result ends.*$//s;
s/<[^>]+>//g; s/[ \n]+/ /gs;
print $_, "\n";

1;
__END__

=head1 NAME

CEG - Currency Exchange Grabber
 
=head1 SYNOPSIS
 
    perl ceg.pl 50 USD JPY
 
=head1 DESCRIPTION
 
    Here is a rough break-down of what each of the ARGV's are needed, and mean:
    perl ceg.pl ($amount) ($cf - convert from) ($ct - convert to)

    This progam's use and reason for being created, is simply for anyone that wants 
    to be able to check the exchange rates for different types of money, such as from 
    other countries.  Say one was going on a trip to Japan, and they live currently in 
    the United States.  They would need to find out how much money they should bring, 
    in order to have a good amount, and there isn't an easier way (almost) than to just 
    enter in the amount you want converted using CEG and telling it to convert from what 
    type of money, to the other country's money.

    It is a very simple program, and is really the first time I have used LWP to do 
    something (useful,) so it could have a lot of new features to add in the future, and 
    possible bug fixes, or efficiency caveats that could be changed, and so on.

=head1 POPULAR CURRENCIES

    Here are a few popular currencies you can use:
      USD - US Dollars
      GBP - UK
      EUR - EURO
      JPY - Japanese Yen

    You can find more at:
      http://www.oanda.com

=head1 HISTORY

    Derived from a snippet from mitd:
      http://www.perlmonks.org/index.pl?node_id=1553&lastnode_id=107998
    Developed by Andy summers on 28/08/2001

=cut

