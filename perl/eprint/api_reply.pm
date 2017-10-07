package eprint::api_reply;

use strict;
use Apache2::Request;
use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY);
use Data::Dumper;
use SOAP::Lite;
use DBI;
use session;

require eprint::api_order;
require eprint::print_project;
require eprint::project;
require eprint::Build;

my %attr = (
        AutoCommit => 0,
        pg_enable_utf8 => 1,
);

my  $dsn = 'dbi:Pg:dbname=empire;';
our $dbh1 =  DBI->connect($dsn, 'postgres');
our $nbh =   DBI->connect($dsn, 'postgres', '', \%attr);

our $serviceProxy   = 'http://64.56.103.94/LqsVendor/lqsvendorquote.asmx'; 
our $serviceNS	    = 'http://www.spi-web.com/';



sub handler {
    my $r = Apache2::Request->new(shift);
use Data::Dumper;

    my $reqs = $dbh1->selectall_arrayref(q{
		SELECT *, now() as today FROM src_req WHERE pending
    }, {Slice => {}}); 
    
print STDERR "API REPLY DBH: ", Dumper($reqs);

    session::r($r);
    session::log($r->log);
    session::dbh($dbh1);

    map { send_response($r, $_) } @{$reqs};

}

sub send_response {
    my $r = shift;
    my $req = shift;

    my $cookie;
    my $var = {
	cust_id => 18,
	user_id => 71 
    };

    print STDERR " Response Handler\n", Dumper($req);



    my $task = $req->{type};
	my $comp;

    if ($task eq 'Order' ) {

		$dbh1->do(q{ UPDATE src_req set pending = false WHERE id = ?  }, undef, $req->{id});

        # process order
		make_order_req($req);

		my $desc = $dbh1->selectrow_array(q{
			SELECT strprojectreference FROM tbl_projects where lngprojectindex = ?
		}, undef, $req->{pid});

		$desc =~ /Print Method (\d*)/;
		my $meth = $1;
		print STDERR "MEHTOD: $meth DESC: $desc FROM PID: $req->{pid} \n";

		my $oid = eprint::api_order::make_order($r,$dbh1,$var, $req);

		parse_result(send_order( $req->{srcid}, $oid, $req->{pid}, $meth), 1) if $oid;

    } elsif ($task eq 'NEW' || $task eq 'R/O CHANGE' || $task eq 'REFERENCE'){

	  # email GLS
	  send_email($r, $req) unless $req->{email_sent};

	  if ( $req->{pid} ) {
		my @data = requote($var, $req, $r->log); 
		parse_result(send_quote(@data));
		$dbh1->do(q{ UPDATE src_req set pending = false WHERE id = ?  }, undef, $req->{id});
	  }

    } elsif ( $task eq 'EXACT R/O' ) {
		$dbh1->do(q{ UPDATE src_req set pending = false WHERE id = ?  }, undef, $req->{id});
		my @data = requote($var, $req, $r->log); 
		parse_result(send_quote(@data));
    }


    return OK if $comp;
 }

sub send_email 	{
	my ($r, $req) = @_;

		use MIME::QuotedPrint     qw(encode_qp);
		my %info;
    	my $email_template = misc::load_file($r, '/site_specific/email/content/empire_api_notification.html');

	print STDERR "EMAIL DATA: ", Dumper($req);

	my $xml;
    open(F, $req->{xml});
    while (<F>) { 
		$xml .= $_; 
	}
    close(F); 
	my @attach = ('src_quote_xml.txt',$xml,'text/html','quoted-printable');

    	$_ = encode_qp( ssi::variable_substitution($r, $r->log, $dbh1, $email_template, $req));

    	my @body = ('', $_, 'text/html', 'quoted-printable');
		my @emails = ('wcober@directionsolutions.com', 'jholm@print-quotes-software.com','ricka@empirescreen.com','richard.varno@gmail.com');
    	my $email_addr = join(',', @emails);
    	my %mail = (
          SMTP    => configuration::get_value($r->log, $dbh1, 'Mail Server'),
          FROM    => configuration::get_value($r->log, $dbh1, 'AdministratorEmail'),
#         FROM    => configuration::get_value($r->log, $dbh1, 'AdministratorEmail'),
          TO      => $email_addr,
          SUBJECT => "New Quote Request",);
	use Data::Dumper;
print STDERR "EMAIL ATTACHE: ", Dumper(@attach);

	misc::send_email_with_attachment($r, $r->log, \%mail, @body, @attach);
	$dbh1->do(q{
		UPDATE src_req set email_sent = true WHERE id = ?
	}, undef, $req->{id});

}

sub make_order_req {
    my $req = shift;
print STDERR "MAKE ORDER REQUEST FOR ESTIMATE: $req->{srcid} \n";
    my $quote = $dbh1->selectrow_hashref(q{
		SELECT * FROM src_req WHERE srcid = ? AND pid is not null
		AND type <> 'Order' order by 1 desc limit 1
    }, undef, $req->{srcid});

    $req->{qtyIndex} = $req->{order_qty} == $quote->{qty1} ? 1 
		     : $req->{order_qty} == $quote->{qty2} ? 2
		     : $req->{order_qty} == $quote->{qty3} ? 3 
		     : undef;

	$req->{pid} = $quote->{pid};

use Data::Dumper;
   print STDERR "ORDER DATA ", Dumper($req, $quote);

	die "QUANTITY NOT FOUND: $req->{order_qty} \n"  unless $req->{qtyIndex};

}

sub requote {

    my ($var, $req, $log) = @_;

    my $jref = $req->{customer} . ' ' . $req->{formno}; 

    my $src = $dbh1->selectrow_array(q{
	SELECT lngprojectindex FROM tbl_projects 
	WHERE strprojectreference = ?
	AND strstatus = 'predefined'
    }, undef, $jref);

    die "PROJECT NOT FOUND -- $jref " unless $src;

    my $args = { };

    my ($pid) = eprint::print_project::copy_project($dbh1, $var, $src, $args);

print STDERR "MAKE NEW PROJECT($pid) FROM PID: $src \n\n";

    update_project_qty($req, $var, $pid);

    eprint::Build::build($log, $nbh, $pid, $var, 1);

    my @price = eprint::project::project_price(
       $log, $dbh1, $pid
    );
    my $date = get_date(); 

    my $out = { 
		SendorID	    	=> '777',
        EstimateNo	    	=> $req->{srcid},
        VendorQuote	    	=> $pid,
		VendorDateQuoted	=> $date,
        QuoteQuantity1	    	=> $req->{qty1},
        Quantity1VendorPrice    => sprintf("%.2f", $req->{qty1} ? $price[0] / $req->{qty1} * 1000 : 0) ,
        Quantity1VendorTurn	=> 0,
        QuoteQuantity2	    	=> $req->{qty2},
        Quantity2VendorPrice    => sprintf("%.2f", $req->{qty2} ? $price[1] / $req->{qty2} * 1000 : 0) ,
        Quantity2VendorTurn	=> 0,
        QuoteQuantity3	    	=> $req->{qty3},
        Quantity3VendorPrice	=> sprintf("%.2f", $req->{qty3} ? $price[2] / $req->{qty3} * 1000 : 0) ,
        Quantity3VendorTurn	=> 0,
        VendorComments	    	=> 'Test CGI Quote',
        VendorBidStatus	    	=> '1' 
    };

    my @data;

    map { push @data, SOAP::Data->name($_ => $out->{$_}) } keys %{$out};
	
	$dbh1->do(q{
		UPDATE src_req set pid = ? WHERE id = ?
	},{}, $pid, $req->{id});

print STDERR "DONE REQUOTE $pid FOR ID: $req->{id}  \n", Dumper($out);

    return @data;
}

sub get_date {
    my @t = localtime(time);
    my $date = $t[5]+1900 .'-'. 
		sprintf("%02d",$t[4]) . '-' . 
		sprintf("%02d",$t[3]) . 'T' . 
		sprintf("%02d",$t[2]) . ':' .
		sprintf("%02d",$t[1]) . ':' .
		sprintf("%02d",$t[0]) . '.000-05:00'
;
	return $date;

}


sub update_project_qty {
    my ($req, $var, $pid) = @_;
    my @qty = (
		$req->{qty1} || 0,
		$req->{qty2} || 0,
		$req->{qty3} || 0
    );
print STDERR "UPDATE QTYS: @qty  - $pid \n";

    # Update the project itself.
    $dbh1->do(q{
        UPDATE tbl_projects
        SET intquantity1 = ?,
            intquantity2 = ?,
            intquantity3 = ?
        WHERE lngprojectindex = ?
    }, undef, (map { $_ || 0 } @qty[0,1,2]), $pid);


    # Each sevice that makes or modifies the project needs to be updated.
    my $specs = $dbh1->prepare(q{
        UPDATE tbl_service_specifications
        SET strvalue = ?
        WHERE strname = 'txtQuantity' || ?::char(1)
          AND lngprojectindex = ?
    });

    for my $i (0..1) {
        next unless $qty[$i] && $qty[$i] > 0;
        $specs->execute($qty[$i], $i+1, $pid);
    }
}



sub send_order {

    my ($src, $oid, $pid, $meth) = @_;

    my $soap = SOAP::Lite 
	->uri($serviceNS) 
	->on_action(sub  { return '"http://www.spi-web.com/VendorOrderConfirm"' })
	->proxy($serviceProxy); 

    my $method =  SOAP::Data->name('VendorOrderConfirm')
	->attr({xmlns => 'http://www.spi-web.com/'});

    my @params = (  
	SOAP::Data->name(SendorID	=> '777'), 
	SOAP::Data->name(SRCQnum	=> $src),
	SOAP::Data->name(VendorQnum	=> $pid),
	SOAP::Data->name(VendorOrderNum => $oid),
	SOAP::Data->name(ProdMethod     => $meth),
	SOAP::Data->name(ErrorMessage	=> '')
    );

print STDERR "SOT1 SENDING ORDER: $oid WITH PROJECT: $pid TO SRC \n";
use Data::Dumper;
print STDERR "DATA ORDER: ", Dumper(\@params);

    return $soap->call($method => @params);

}

sub send_quote {
    my @data = @_;

map { print STDERR "DATA: " .  $_->name() . " => " . $_->value() . "\n";} @data;

    my $soap = SOAP::Lite
      ->uri($serviceNS)
      ->on_action(sub  { return '"http://www.spi-web.com/VendorQuote"' })
      ->proxy($serviceProxy);

    my $method =  SOAP::Data->name('VendorQuote')
      ->attr({xmlns => 'http://www.spi-web.com/'});

    return $soap->call($method => @data);
}

sub parse_result {

    my $result = shift;
	my $order  = shift;
#print STDERR "PARSE RESULT " , Dumper($result);

    unless ($result->fault) {
	 print STDERR "<h3>No Fault</h3>";
	 my $statusmes = $order ? $result->valueof('//VendorOrderConfirmResponse/VendorOrderConfirmResult')
						    : $result->valueof('//VendorQuoteResponse/VendorQuoteResult');

	 print STDERR "<p>message: " . $statusmes . "\n";

     } else {
	# some error handling
	print STDERR "<h3>Fault Occurred</h3>";
	print STDERR join ', ',
	 $result->faultcode,
	 $result->faultstring,
	 $result->faultdetail;
     }

}



;

