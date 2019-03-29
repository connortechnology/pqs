package eprint::mat_inventory;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use strict;

use session;

use Data::Dumper;

use PQS::Object::project;
use DateTime;
use DateTime::Format::Strptime;
use eprint::project;

our $dbh = session::dbh;

our $cols = [
	{ desc=>"ID", 					id=>"id", 					class=> "rgfield", ro=>1 },
	{ desc=>"Description", 			id=>"name", 				class=> "lgfield", ro=>1 },
	{ desc=>"On Hand", 				id=>"onhand", 				class=> "srfield", ro=>1 },
	{ desc=>"Allocated", 			id=>"onorder", 				class=> "srfield", ro=>1 },
	{ desc=>"Net Count", 			id=>"netcount", 			class=> "srfield", ro=>1 },
#	{ desc=>"Contact", 				id=>"contact", 				class=> "rgfield", ro=>1 },
#	{ desc=>"Stock", 				id=>"stock", 				class=> "lgfield", ro=>1 },
#	{ desc=>"P", 					id=>"pulled", 				class=> "tifield", ro=>1 },
	];
  
sub add_link {
    my $x = shift;
    my $l = shift;

    $x->{link} = "/main/order/order_history_details.html?order_id=$x->{value}" if $x->{id} eq 'lngorderid';
    $x->{link} = "/main/proj/proj_view.html?pid=$x->{value}" if $x->{id} eq 'lngprojectindex';
    $x->{link} = "/administrator/managerial/company_profiles.html?ddmCustomer=$l->{lngcustomerid}" if $x->{id} eq 'strcompanyname';
    $x->{link} = "/administrator/managerial/user_profiles.html?ddmUser=$l->{lnguserindex}" if $x->{id} eq 'contact';
    $x->{link} = "/main/proj/proj_view.html?pid=$l->{lngprojectindex}" if $x->{id} eq 'strprojectreference';
    $x->{link} = "/main/proj/edit.html?pid=$l->{lngprojectindex}" if $x->{id} eq 'intquantity1';
    $x->{link} = "/service/shipping?pid=$l->{lngprojectindex};sid=$l->{shipid}" if $x->{id} eq 'delivery';
    $x->{link} = "/service/printing?pid=$l->{lngprojectindex};sid=$l->{lngserviceindex}" if $x->{id} eq 'stock';
    $x->{link} = "/main/quote/quote_history_details.html?quote_id=$l->{lngquoteid};" if $x->{id} eq 'lngquoteid';


}

sub sql_filters {

	my $param = shift;
	my $type = shift;
	my $dbh	= session::dbh;

	my $list = $dbh->selectall_arrayref(q{SELECT itable, field, label FROM inventory_filters WHERE itype =?}, {Slice=>{}}, $type); 

	map {
		$_->{input} = 'fltr' . $_->{label}; 
		$_->{col} = $_->{itable} . '.' . $_->{field}; 
	} @{$list};


	#	my $list = [
	#	{ input => 'ddmCompanyName', 	col => 'p.lngcustomerid' },
	#	{ input => 'ddmSalesRep',    	col => 'c.lngsalesperson' },
	#	{ input => 'ddmOrderBy',     	col => 'p.lnguserindex' },
	#	{ input => 'ddmProjectStatus',  col => 'p.strstatus' },
	#	{ input => 'ddmCSR',  			col => 'c.csr' },
	#];



	my $text; 
	foreach my $f ( @{$list} ) {
		$text .= " AND $f->{col} = " . "'" .  "$param->{$f->{input}}" . "'" if $param->{$f->{input}};
	}

	#	if (  $param->{textsearch} && $param->{search_type} eq 'strprojectreference' ) {
	#
	#	my $searchstring = lc($param->{textsearch});
	#	$searchstring =~ s/'//g;
	#
	#	my @words = split(' ', $searchstring);
	#
	#	#$searchstring = '%' . join('%', @words) . '%';
	#
	#	map {
	#		$text .= qq{ AND lower(strprojectreference) LIKE  '\%$_\%' \n}  
	#	} @words;
	#}
	#
	#if ( $param->{startdate} && $param->{enddate} ) {
	#	$text .= q{AND p.dtmcreationdate BETWEEN '} . $param->{startdate} . q{ 1:00am' AND '} . $param->{enddate} . q{ 11:59pm'};
	#} elsif( $param->{startdate} ) {
	#	$text .= q{AND p.dtmcreationdate > '} . $param->{startdate} . q{ 1:00am'};
	#}
	# 

	#$text .= qq{ AND lower(strprojectreference) LIKE  '$searchstring'}  


	print STDERR "HAVE TEXT: $text \n", Dumper($list, $param);
	return $text;

}

sub dashboard_defaults {
	my $param = shift;

	$param->{itype} = 'stock' unless $param->{itype} ;

	return $param;
}

sub get_data {
	my $param = shift;
	my $type = shift;
	my $col_list = shift;

	my $dbh = session::dbh;

	my $sql_filter = sql_filters($param, $type);
	my $table;
	my $and;

	if ( $type eq 'product' ) {
		$table = 'tbl_products';
		$and = ' AND tbl_products.strid = i.id';
	} else {
		$table = 'tbl_paper';
		$and = ' AND tbl_paper.strid = i.id';
	}
	my $sql = qq{
		SELECT *, onhand - onorder as netcount 
		FROM  
		mat_inventory i, inventory_count ic, $table
	   	WHERE itype = ? 
		AND i.id = ic.id
		$and

		$sql_filter

		ORDER by 1 DESC

		--LIMIT 2 
	};

	my $lines = $dbh->selectall_arrayref( $sql, {Slice => {}}, $type );

print STDERR "HAVE SQL: $sql \n";


	my @data;

	my $sortfield = $param->{sortfield};

	print STDERR "HAVE SORT FIELD: $sortfield \n";

	foreach my $l ( @{$lines} ) {


		my $d = {};
		foreach my $c ( @{$col_list} )  {
			my %x = %{$c};


			$x{value} = $l->{$c->{id}};
			
			add_link(\%x, $l);


			push @{$d->{fields}}, \%x; 
			$d->{sortdata} = $l->{$sortfield};
			$d->{id} = $l->{id};

		}


		#print STDERR "HAVE DATA: ",Dumper($l);
		push @data, $d;
	}


	#print STDERR "HAVE DATA X: ", Dumper(\@data);
	print STDERR "# of Records: ", scalar @data , "\n";
	return @data;

}

sub text_search {
	my $param = shift;
	my $var   = shift;

	my $r = session::r;
	my $log = session::log;
	my $dbh	= session::dbh;

	my $search_type = $param->{search_type};

}

sub update_inventory {

	my $param = shift;
	my $dbh	= session::dbh;

	print STDERR "UPDATE INVENTORY \n";

	map { 
		my $key = $_;
		my $val = $param->{$_};
		if ( $key =~ /onhand-(.*)/ && $val ) {
			print STDERR "UPDATE $_ ID: $1 \n";
			$dbh->do(q{Update inventory_count set onhand = ? WHERE id = ?}, undef, $val, $1);

		}
		if ( $key =~ /onorder-(.*)/ && $val ) {
			print STDERR "UPDATE $_ ID: $1 \n";
			$dbh->do(q{Update inventory_count set onorder = ? WHERE id = ?}, undef, $val, $1);

		}
	} keys %{$param};
}


sub display {
	my $param 	= shift;
	my $var 	= shift;

	if ( $param->{save} ) {
		update_inventory($param);
	}

	if ( $param->{textsearch} ) {
		text_search($param, $var);
		return if $var->{Redirect};
	}



	$param = dashboard_defaults($param);

	my $type = $param->{itype};

	my @col_list = @{$cols};

	splice @col_list, 1,1 if $type eq 'Order'; 
	splice @col_list, 0,1 if $type eq 'Quote'; 


	
	my @data = get_data($param, $type, \@col_list);



	apply_sort(\@data, $param);


	$var->{fields} = \@col_list;


	$var->{data} = \@data;

	$var->{FILTERS} = make_filters($type);




	#Always Reset action box before loading page
	$param->{action} = undef;
	$param->{actionpid} = undef;
	$param->{selectall} = undef;

	map { $var->{__FillInForm}{$_} = $param->{$_} } keys %{$param};


	return ;

}

sub make_filters {
	my $type = shift;
	my $dbh = session::dbh;

	my $data = $dbh->selectall_arrayref(q{SELECT * FROM inventory_filters WHERE itype = ?}, {Slice => {} }, $type );

	print STDERR "HAVE FILTES", Dumper($data);

	my @filters;
	foreach my $d ( @{$data} ) {
		my $f;
		$f->{name} = $d->{label}; 	
		$f->{id} = $d->{label}; 	
		$f->{label} = $d->{label}; 	
		my $text = $d->{option_sql};
		my $list = $dbh->selectall_arrayref($text); 
		die("NO OPTIONS: $text") unless $text;

		$f->{OPTIONS} = ssi::make_drop_down($list);
	push @filters, $f;
	}

	print STDERR "HAVE FILTES", Dumper(\@filters);

	return \@filters;

}


sub apply_sort {
	my $data = shift;
	my $param = shift;


	my $x = int($$data[0]->{sortdata});

	my $y = $$data[0]->{sortdata};

	use Scalar::Util qw( looks_like_number );

	if ( looks_like_number($$data[0]->{sortdata}) ) {
	    @{$data} = sort { $a->{sortdata} <=> $b->{sortdata} } @{$data};
	} else { 
	    @{$data} = sort { $a->{sortdata} cmp $b->{sortdata} } @{$data};
	}
	if ( $param->{sortdirection} == -1 ) {

		print STDERR "REVERSE SORT \n";
	    @{$data} = reverse @{$data};
	}
}





1;

__END__
~       
