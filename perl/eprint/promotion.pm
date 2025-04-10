package eprint::promotion;

use Apache2::Const qw(:common HTTP_MOVED_TEMPORARILY); # Offers OK, Error, etc for web server.
use strict;

use session;

use Data::Dumper;

use PQS::Object::project;
use DateTime;
use DateTime::Format::Strptime;
use eprint::project;
use PQS::model::promo;

use PQS::Object::promotion;

our $dbh = session::dbh;

our $cols = [
	{ desc=>"ID", 					id=>"id", 					class=> "rgfield", ro=>1 },
	{ desc=>"Name", 				id=>"name", 				class=> "rgfield", ro=>1 },
	{ desc=>"Title", 				id=>"title", 				class=> "srfield", ro=>1 },
	{ desc=>"Description", 			id=>"description", 			class=> "lgfield", ro=>1 },

#	{ desc=>"Contact", 				id=>"contact", 				class=> "rgfield", ro=>1 },
#	{ desc=>"Stock", 				id=>"stock", 				class=> "lgfield", ro=>1 },
#	{ desc=>"P", 					id=>"pulled", 				class=> "tifield", ro=>1 },
	];
  
sub add_link {
    my $x = shift;
    my $l = shift;

    $x->{link} = "promotion_edit.html?id=$x->{value}" if $x->{id} eq 'id';
	#$x->{link} = "/main/proj/view.html?pid=$x->{value}" if $x->{id} eq 'lngprojectindex';



}

sub text_search {
	my $string = shift;
	my $dbfield = shift;

	print STDERR "START TEXT SEARCH \n";

	my $text;

	if (  $string ) {

	
		my $searchstring = lc($string);
		$searchstring =~ s/'//g;
	
		my @words = split(' ', $searchstring);
	
		$searchstring = '%' . join('%', @words) . '%';
	
		map {
			$text .= qq{ AND lower($dbfield) LIKE  '\%$_\%' \n}  
		} @words;

	}

	print STDERR "HAVE TEXT SEARCH: $text \n";
	return $text;


}

sub sql_filters {

	my $param = shift;
	my $type = shift;


	print STDERR "START SQL FILTER \n";
	#	my $list = [
	#	{ input => 'ddmCompanyName', 	col => 'p.lngcustomerid' },
	#	{ input => 'ddmSalesRep',    	col => 'c.lngsalesperson' },
	#	{ input => 'ddmOrderBy',     	col => 'p.lnguserindex' },
	#	{ input => 'ddmProjectStatus',  col => 'p.strstatus' },
	#	{ input => 'ddmCSR',  			col => 'c.csr' },
	#];



	my $text; 
	#foreach my $f ( @{$list} ) {
	#	$text .= " AND $f->{col} = " . "'" .  "$param->{$f->{input}}" . "'" if $param->{$f->{input}};
	#}


	$text .= text_search($param->{search_name}, 'name');
	$text .= text_search($param->{search_title}, 'title');
	$text .= text_search($param->{search_description}, 'description');

	#
	#if ( $param->{startdate} && $param->{enddate} ) {
	#	$text .= q{AND p.dtmcreationdate BETWEEN '} . $param->{startdate} . q{ 1:00am' AND '} . $param->{enddate} . q{ 11:59pm'};
	#} elsif( $param->{startdate} ) {
	#	$text .= q{AND p.dtmcreationdate > '} . $param->{startdate} . q{ 1:00am'};
	#}
	# 

	#$text .= qq{ AND lower(strprojectreference) LIKE  '$searchstring'}  


	print STDERR "HAVE TEXT: $text \n";
	return $text;

}

sub dashboard_defaults {
	my $param = shift;

	$param->{itype} = 'stock' unless $param->{itype} ;

	return $param;
}

sub get_data {
	my $param = shift;
	my $col_list = shift;


	print STDERR "START GET DATA \n";
	my $dbh = session::dbh;

	my $sql_filter = sql_filters($param);

	my $sql = qq{
		SELECT *
		FROM  
		promo
	   	WHERE 1>0

		$sql_filter

		ORDER by 1 DESC

	};

	my $lines = $dbh->selectall_arrayref( $sql, {Slice => {}});

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


sub update_inventory {

	my $param = shift;

	print STDERR "UPDATE INVENTORY \n";

	map { 
		my $key = $_;
		my $val = $param->{$_};
		if ( $key =~ /onhand-(.*)/ && $val ) {
			print STDERR "UPDATE $_ ID: $1 \n";
			$dbh->do(q{Update inventory_count set onhand = ? WHERE id = ?}, undef, $val, $1);

		}
	} keys %{$param};
}

sub save_edit {
	my $param 	= shift;
	my $var 	= shift;

	print STDERR "HAVE PARAM", Dumper($param);

	die("Missing Parameter Name") unless $param->{id} || $param->{name};

	my $id =  $param->{id} || PQS::model::promo::insert($param->{name});	

	my $promo = new PQS::Object::promotion($param->{id});

	$promo->formtodb($param);



	print STDERR "HAVE PARAM", Dumper($param);

}

sub list {
	my $param 	= shift;
	my $var 	= shift;

	$param = dashboard_defaults($param);
	
	my @col_list = @{$cols};
	my @data = get_data($param, \@col_list);

	apply_sort(\@data, $param);


	$var->{fields} = \@col_list;


	$var->{data} = \@data;

	map { $var->{__FillInForm}{$_} = $param->{$_} } keys %{$param};



	return ;

}

sub edit {
	my $param 	= shift;
	my $var 	= shift;

	my $promo = new PQS::Object::promotion($param->{id});

	if ($param->{save} ) {
		#save_edit($param);
		$promo->formtodb($param);
	} elsif( $param->{delete} ) {
		$promo->self_destruct;
		$var->{Redirect} = "/administrator/marketing/promotions.html";
	}



	#	map { $var->{__FillInForm}{$_} = $param->{$_} } keys %{$param};

	map { $var->{__FillInForm}{$_} = $promo->{specs}{$_} } keys %{$promo->{specs}};
	
	$var->{MARKETING_CATEGORIES} = ssi::select_options(qw(tbl_marketing_categories lngindex strname));

	$var->{PRODUCT_CATEGORIES} = ssi::select_options(qw(categories id name));



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
