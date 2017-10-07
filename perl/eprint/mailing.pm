package eprint::mailing;
use strict;

use Data::Dumper;
use eprint::order;
use session;

use eprint::project qw(get_path);

use constant MAILCAT => qw( late new lapsed lapse30 lapse60 );
use constant MAILDATE => q{ (last_mail::date < now() - '30 days'::interval OR last_mail is NULL) };
	

sub handler {
	my ($r, $dbh, $var) = @_;
print STDERR "**** MAILNG HANDLER **** \n";
print STDERR "HAVE CAT" , Dumper(MAILCAT);

#	record_count($r, $dbh, $var) 					if  $r->param('record_count');
    session::r($r);
    session::log($r->log);
    session::dbh($dbh);

	add_to_order($r, $dbh, $var, $r->param('add_pid')) 	if  $r->param('add_pid');

	record_count($r, $dbh, $var);

}

sub add_to_order {
	my ($r, $dbh, $var, $pid) = @_;
	eprint::order::add_project_to_order($r->log, $dbh, $var->{cookie}, $var, $pid);	

	
}

sub record_count {
	my ($r, $dbh, $var) = @_;

	my $cust = $var->{user}{company}{name};

	my $sql = 
		q{ SELECT count(*) from marketing_data WHERE mail_type = ? } 
		. 'AND ' . MAILDATE .
		q{ AND location = ? };

	map {
	print STDERR "HAVE SQL: $sql \n";
		$var->{"count_$_"} = $dbh->selectrow_array($sql , undef, $_, $cust);
	} MAILCAT;


	my $order_id = eprint::order::get_unfinished_order( 
				$r->log, $dbh, $var->{cookie}, $var->{cust_id}, $var->{user_id} );
	my $data;
	if ( $order_id ) {
		 $data = $dbh->selectcol_arrayref(q{
			SELECT mail_type FROM tbl_projects p , tbl_order_contents c
			WHERE p.lngprojectindex = c.lngprojectindex 
			AND c.lngorderid = ?
		},undef, $order_id);
		map {$var->{ordered}{$_} = 1} @{$data};
	}

print STDERR "GET RECORD COUNT FOR: $cust  **** \n", Dumper($var, $order_id, $data);

}

sub reserve_mail {
    my ($r, $dbh, $var, $pid, $qty) = @_;
	my $list = lc $r->param('mail_type');
	my $cust = $var->{user}{company}{name};

	die("Invalid Quantity: $qty -- Template::insert_mail") unless $qty;
	die("Invalid Mailing Type ( param('mail_data') ) -- Template::insert_mail") unless $list;


	my $where = q{ WHERE mail_type = ? AND } . MAILDATE . q{AND location = ? };


	my $order = q{ ORDER BY last_mail DESC };
	my $limit = qq{LIMIT $qty}; 

	my $sql = qq{SELECT * FROM marketing_data $where $order $limit};

	my $data = $dbh->selectall_arrayref($sql,{Slice => {}}, $list, $cust);

print STDERR "DATA LOOKUP : \n $sql \n", Dumper($data);

	foreach my $rec ( @{$data} ) { 
		$dbh->do(q{
			UPDATE marketing_data SET last_pid = ? 
			WHERE location = ? AND mail_type = ?
			AND customer = ?
		}, undef, $pid, $cust, $list, $rec->{customer});

print STDERR "D0 RESERVE Mail $pid, $cust, $list, $rec->{customer} \n";

	} # new end while

	
}

sub make_address_file {
	my ($r, $dbh, $var, $pid) = @_;

	my $file  = get_path(undef, $dbh, $pid) . '.template/mailing_address.csv';

	my $type = 'csv';

    my $csv = Text::CSV_XS->new({
            binary   => 1, # Allow UTF-8 (and embedded newlines)
            sep_char => $type eq 'tsv' ? "\t" : ',',
			eol		 => $/,
    });	
	
	my $fields = q{ location, name, customer, street_name, suite, city, province, postal_code, phone, mail_type, last_order, delivery_minutes };

	my $sth = $dbh->prepare(qq{
		SELECT $fields from marketing_data WHERE last_pid = ?
	});
	$sth->execute($pid);


	my $fh;

	open $fh, ">:encoding(utf8)", $file or die "$file: $!";

	while (my $rec = $sth->fetch) { 
		$csv->print ($fh, $rec);
	}

 	close $fh or die "$file: $!";
}



1;
