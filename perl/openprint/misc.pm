use strict;
package openprint::misc;
use strict;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw( load_file send_email_with_attached_files send_email_with_attachment build_city_prov_country export_csv export get_destination);

use Text::CSV_XS ();
use Date::Calc qw(Add_Delta_Days);
use Date::Format qw( time2str );

#use Mail::Sendmail ();

use openprint ();

sub send_email_with_attached_files {
	my ( $r, $log, $mail, @attachments ) = @_; 

	for ( my $index = 0; $index < @attachments; $index += 4 ) {

		open ( F, $attachments[$index+1] ) or $log->error( "Can't open " . $attachments[$index+1] );;
		binmode F; undef $/;
		my $text = '';
		foreach my $curline (<F>) {
			$curline =~ s/\n/\r\n/g;
			$text .= $curline;
		} #end foreach
		close F;
		$attachments[$index+1] =$text;
	} # end for
	send_email_with_attachment( $log, $mail, @attachments );
} # end sub send_email_with_attached_files

sub send_email_with_attachment {
	my ( $log, $mail, @attachments ) = @_; 

	if ( @attachments ) {
		my $message = $$mail{BODY};

		my $boundary = $$mail{BOUNDARY} ? $$mail{BOUNDARY} : ( "====" . time() . "====" );
		$$mail{'content-type'} = "multipart/mixed;\r\n	boundary=\"$boundary\"\r\n";

# start with the current body
		$$mail{BODY} .= "This is a multi-part message in MIME format.\n\n";
		if ( $message ) {
			$$mail{BODY} .= "--$boundary\n";
			$$mail{BODY} .= ($$mail{'content-type'} ? $$mail{'content-type'} : 'Content-Type: text/plain; charset="utf-8"')."\n";
			$$mail{BODY} .= "Content-Transfer-Encoding: 8-bit\n";
			$$mail{BODY} .= "\n$message\n";
		} else {
			my ( $name, $text, $type, $encoding ) = splice @attachments,0,4;
			$$mail{BODY} .= "--$boundary\nContent-Type: $type;\n";
			$$mail{BODY} .= "Content-Transfer-Encoding: $encoding\n";
			$$mail{BODY} .= "\n$text\n";
		} # end if

		while ( @attachments ) {
			my $name = shift @attachments;
			my $text = shift @attachments;
			my $type = shift @attachments;
			my $encoding = shift @attachments;
			$$mail{BODY} .= "--$boundary\nContent-Type: $type;\n";
			$$mail{BODY} .= "\tname=\"$name\"\n" if $name;
			$$mail{BODY} .= "Content-Transfer-Encoding: $encoding\n";
			$$mail{BODY} .= "Content-Disposition: attachment;\n";
			$$mail{BODY} .= "\tfilename=\"$name\"\n" if $name;
			$$mail{BODY} .= "\n$text\n";
		} # end while

# Signal end of attachments
		$$mail{BODY} .= "--$boundary--\n\n";
	} # end if
	#Mail::Sendmail::sendmail(%{$mail}) || $log->error( "Error: $Mail::Sendmail::error\n" );
	$log->error("Deprecated");
} # end sub send_email_with_attachment

# Loads the specified file and returns it.	Returns undef on failure.
sub load_file {
	my ( $log, $file ) = @_;

	if ( open( TEMPLATE, "< $file" ) ) {
		my $contents = '';
		while ( <TEMPLATE> ) {
			$contents .= $_;
		} # end while
		close( TEMPLATE );
		return $contents;
	} # end if

	$log->warn( "Error opening $file, Reason: $!" );
	return undef;
} # end sub load_file

sub save_file {
	my ( $log, $file, $contents ) = @_;
	if ( ! $contents ) {
		$log->warn("Saving empty file $file");
	} # end if
	if ( open( F, "> $file" ) ) {
		binmode F;
		print F $contents;
		close F;
	} else {
		$log->warn( "Error opening $file, Reason: $!" );
		return "Error opening $file, Reason: $!";
	} # end if
	return;
} # end sub save_file

sub build_city_prov_country {
	my ( $city, $prov, $country ) = @_;
	my $cpc = $city;

	if ( $prov ) {
		$cpc .= ', ' if $cpc;
		$cpc .= $prov;
	} # end if

	if ( $country ) {
		$cpc .= ', ' if $cpc;
		$cpc .= $country;
	} # end if;
	return $cpc;
} # end sub build_city_prov_country

sub data_to_csv {
	my ( $header, $data, $options ) = @_;
  $options = {'binary'=>1} if ! $options;

	my @data;
	my $csv = Text::CSV_XS->new($options);

	my $columns = scalar @{$header};
	$csv->combine( @{$header} );	# combine columns into a string
	push @data, $csv->string() . "\n";

	for ( my $index = 0; $index < @{$data}; $index += 1 ) {
		next if ! defined($$data[$index]);
		$$data[$index] =~ s/[\n\r]//g; # these really mess up the CSV
	} # end for
	
	while ( @{$data} ) {
		my $status = $csv->combine( splice( @{$data}, 0, $columns ) );	# combine columns into a string
		push @data, $csv->string() . "\n";
	} # end while

	return @data;
} # end sub data_to_csv

sub csv_to_file {
  my ($file, $header, $data, $options) = @_;
  my @output = data_to_csv($header, $data, $options);
  open (my $fh, '>', $file) or die "Unable to open file $file $!";
  print $fh  join('', @output);
  close $fh;
}

sub export_csv {
	my ( $r, $log, $variable, $filename, $header, $data ) = @_;
	if ( scalar @{$header} <= 0 ) {
		$log->error('Invalid Header!');
		return;
	} # end if
	my @data = data_to_csv( $header, $data );

	$r->headers_out->{'Content-Disposition'} = "attachment; filename=\"$filename\"";
	$r->content_type( "text/csv; name=\"$filename\"" );
	#$r->content_encoding( "binary" );
	$$variable{Download} = \@data;
} # end sub

sub export {
	my ( $r, $log, $variable, $filename, $data ) = @_;
	$r->headers_out->{'Content-Disposition'} = "attachment; filename=\"$filename\"";
	$r->content_type( "application/octet-stream; name=\"$filename\"" );
	#$r->content_encoding( "binary" );
	$$variable{Download} = $data;
} # end sub export

sub get_destination {
	my ( $r, $uri ) = @_;
	my $dest = $uri ? $uri : $r->uri();
	my @values;
	foreach my $key ( $r->param() ) {
		next if $key eq 'password';
		push @values, map { $key.'='.$_ } ( ref $r->param($key) eq 'ARRAY' ? @{$r->param($key)} : $r->param($key) );
	} # end ofreach     
	if ( @values ) {
		$dest .= '?' . join('&', @values );
	} # end if
	return $dest;
} # end sub get_destination

sub get_url {
	my ( $uri, $params, $options ) = @_;
	my @keys = keys %$params;
	if ( $options and $$options{exclude} ) {
		@keys = sets::exclude( (ref $$options{exclude} eq 'ARRAY' ? $$options{exclude} : [ $$options{exclude} ]), \@keys );
	} # end if	
	@keys = sets::exclude( [ 'password', 'btnFunction', 'email','select_currency_id','ddmCompany','CompanyFilter','pricelist_id' ], \@keys );
	my %encoded;
	foreach my $k ( @keys ) {
		if ( ref $$params{$k} eq 'ARRAY' ) {
			$encoded{$k} = join( ',', @{$$params{$k}} );
		} else {
			$encoded{$k} = $$params{$k};
		}
		$encoded{$k} =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;	
	} # end foreach
	if ( $options and $$options{include} ) {
		foreach my $k ( keys %{$$options{include}} ) {
			$encoded{$k} = $$options{include}{$k};
		} # end foreach
	} # end if	

	return join( '?', $uri, join('&amp;', map { $_.'='.$encoded{$_} } keys %encoded ) );
} # end sub get_url

sub sum {
	my $sum = 0;
	foreach ( @_ ) {
		$sum += $_;
	} # end foreach
	return $sum;
} # end sub sum

sub error {
	my ( $log, $dbh, $variable, $error, $details ) = @_;
	$log->debug("Error: $error");
	$log->debug("Details: $details");

	$$variable{error} = $error;
	$$variable{details} = $details;
	$$variable{information} = $details;
	#$$variable{Redirect} = $openprint::config{errorpage};
} # end sub error

sub trim {
	my @results;
	foreach my $thing ( @_ ) {
		s/^\s+//, s/\s+$// for $thing;
		push @results, $thing;
	}
	return @results;
}

sub moneyfilter {
	$_ = shift;
	if (/.*?(?:\$\s*)?(\-?[0-9]+(\.[0-9]{1,2})?).*?/) {
		if ( $1 > 10000000 ) {
			return 10000000;
		}
		return $1;
	} else {
		return undef;
	}
} # end sub moneyfilter

sub seconds_to_interval {
	$_[0] = int $_[0];
	my $h = int ($_[0]/3600);
	my $m = $_[0] - ($h*3600);
	return ( $h, int($m/60), $m%60 );
}

sub seconds_to_JDF_interval {
	$_[0] = int $_[0];
	my $d = int ($_[0]/86400);
	$_[0] -= $d*86400;
	my $h = int ($_[0]/3600);
	my $m = $_[0] - ($h*3600);
	my $return;
	$return .= $d.'D' if $d;
	$return .= $h.'H' if $h;
	$return .= int($m/60).'M' if int($m/60);
	$return .= ($m%60).'S' if $m%60;

	return $return;
}

sub seconds_to_pretty_interval {
	my ( $seconds ) = @_;
	my $string;
	my $years = int($seconds / ( 60 * 60 * 24 * 365 ));
	my $remainder = $seconds % ( 60*60*24*365 );
	$string .= sprintf('%dy', $years) if $years;
	return $string if ! $remainder;

	my $days = int ( $remainder / ( 60* 60 * 24 ) );
	$remainder = $remainder % ( 60 * 60 * 24 );
	if ( sets::isin($days, [ 28,29,30,31 ]) ) {
$openprint::log->debug("Remainder: $remainder from $seconds");
    if ( (! $remainder) or ( $remainder == 82800 ) or ($remainder==3600)) {
      # 2600 is for dst change in november
      $string .= '1 month';
      return $string;
    }
	}
 #else {
    #if ( $remainder and ! ( $remainder % (60*60 ) ) ) {
      #$string .= $days * 24 + ( $remainder / 3600 ).'h'; 
      #$remainder = 0;
    #} elsif ( $days ) {
      #$string .= sprintf('%dd', $days );
    #}
	#} # end if
	#return $string if ! $remainder;

	$string .= seconds2hms( $days * 60 * 60 * 24 + $remainder );
	return $string;
} # end sub seconds_to_pretty_interval

sub interval_to_seconds {
	my $interval = shift;
	my ( $h, $m, $s ) = split ':', $interval;
	return ($h*3600) + ($m*60) + $s;
} # end sub interval_to_seconds

sub rle_decode {
	my ( $source, $width, $height ) = @_;
	my $result = '';
	my $position = 0;
	while ( $source ) {
		my $l = unpack( 'C', $source );
		if ( $l == 128 ) {
			# Could be end of scan line
			substr($source, 0, 1) = '';
#$openprint::log->warn("scanline length: $position");
#$position = 0;
		} elsif ($l > 128) {
			if (length($source) < 2) {
				$openprint::log->warn("Premature end to data in RunLengthEncoded data");
				return $result;
			} # end if
			$result .= substr($source, 1, 1) x (257 - $l);
			substr($source, 0, 2) = '';
			$position += 2;
		} else {
			if (length($source) < $l + 1) {
				$openprint::log->warn("Premature end to data in RunLengthEncoded data");
				return $result;
			}
			$result .= substr($source, 1, $l+1);
			substr($source, 0, $l + 2) = '';
			$position += $l+2;
		}
	} # end while source
	return $result;
} # end sub rle_decode

# We do not encode single chars, must be more than 2.
sub rle_encode {	
	my $input = $_[0];
	my $output;

	my $last = '';
	my $count = 0;

	while ( $input ) {
		my $next = substr($input, 0, 1);
		substr($input, 0, 1) = '';

		if ( $next ne $last ) {
			if ( $count == 1 ) {
				$output .= pack( 'C', 2 );
				$output .= $last.$next;;
				$count = 0;
				$last = '';
			} elsif ( $count > 1 ) {
				$output .= pack( 'C', 257-$count );
				$output .= $last;
				$last = $next;
				$count = 1;
			} else {
				$last = $next;
				$count = 1;
			} # end if
		} else {
			if ( $count == 127 ) {
				$output .= pack( 'C', 257-$count );
				$output .= $last;
				$count = 0;
			} # end if
			$count += 1;
		} # end if
	} # end while
	if ( $count ) {
		$output .= pack('C', 257-$count );
		$output .= $last;
	} # end if
	return $output. (pack('C', 128));
} # end sub rle_encode

sub hms2time {
	my ($h,$m,$s) = split(':', $_[0]);
	return ($h*3600) + ($m*60) + $s;
} # end sub hms2time

sub format_bytes {
	$_[1] = '.3' if ! $_[1];
	if ( $_[0] > 1048576 ) {
		return sprintf( "%$_[1]f MB", $_[0] / 1048576 );
	} elsif ( $_[0] > 1024 ) {
		return sprintf( "%$_[1]f KB", $_[0] / 1024 );
	} else {
		return $_[0].' B';
	} # end if
} # end sub format_bytes

sub seconds2hm {
  my ( $seconds ) = @_;
  my $hours = int( $seconds / (60*60) );
  $seconds = $seconds % ( 60*60 );
  my $minutes = int ( $seconds / 60 );

  return sprintf('%d:%.2d', $hours, $minutes );
} # end sub seconds2hm

sub seconds2hms {
	my ( $seconds ) = @_;
	my $hours = int( $seconds / (60*60) );
	$seconds = $seconds % ( 60*60 );
	my $minutes = int ( $seconds / 60 );
	$seconds = $seconds % 60;

	if ( $seconds ) {
		return sprintf('%d:%.2d:%.2d', $hours, $minutes, $seconds );
	} # end if
	return sprintf('%d:%.2d', $hours, $minutes );
} # end sub seconds2hms

sub find_entry {
	my ( $range, $array, $debug ) = @_;

	if ( ! defined $range ) {
		if ( @{$array} ) {
#foreach my $k ( @{$array} ) {
#$openprint::log->debug("Looking for undef range, sending back first entry which is " . $k->to_string() );
#}
			return $$array[0];
		} # end if
		return;
	} # end if
	my $name = $$array[0]{name};
	$openprint::log->debug("Looking for $name : $range") if $debug;

	my $i = 0;
	my $x;
	my $y;
	for ( ; $i < @{$array}; $i += 1 ) {
		my $Object = $$array[$i];
	$openprint::log->debug("Examining: min(" . $$Object{min} . 	') max(' . $$Object{max} . ') value(' . $$Object{value} . ') interpolate('.$$Object{interpolate} .')') if $debug;
		return $Object if ( $$Object{min} <= $range ) and ( ( $$Object{max} eq '' ) or ( $$Object{max} >= $range ) );

		# first step, find one less than the min
		last if $$Object{min} > $range;
		#last if ( $Object->max() eq '' and ! $Object->interpolate() );
	} # end if
	
	if ( $i and $i <= @{$array} ) {
		$i -= 1;
		# back up
		$x = $$array[$i];
$openprint::log->debug("Found spec for $range:" . $x->min() . ' ' . $x->max() . ' : ' . $x->value() ) if $debug;
		return if ( $$x{max} and ( $$x{max} < $range ) and ! $$x{interpolate} );
	} else {
$openprint::log->debug("Couldn't find minimum for $name : $range on " . ( $$array[0]->Equipment() ? $$array[0]->Equipment()->name() : '' ) ) if $debug;
		return;	
	}
	for ( ; $i < @{$array}; $i += 1 ) {
		my $Object = $$array[$i];
		return $Object if ( (1*$$Object{min}) <= $range ) and ( ( (1*$$Object{max}) >= $range ) or ! (1*$$Object{max}) );

	$openprint::log->debug("Examining: ($range) (" . $Object->min() . 	') (' . 1*$Object->max() . ') (' . $Object->value() . ') ('.$Object->interpolate() ) if $debug;
		# first step, find one less than the min
		last if ( ( (1*$$Object{max}) > $range) or ( ! (1*$$Object{max}) ) );
	} # end foreach
	if ( $i and $i < @{$array} ) {
		$y = $$array[$i];
		$openprint::log->debug('Found spec max '.$y->min().' '.$y->max().' : '.$y->value()) if $debug;
	} else {
		$openprint::log->debug("Couldn't find maximum for $name") if $debug;
		return;
	} # end if

	if ( $x == $y ) {
		return $x;
	} elsif ( $$x{interpolate} ) {
		my $Object = $x->copy();
		$$Object{min} = $$Object{max} = $range;
		$$Object{value} = $$x{value} + ($range - $$x{min})*($$y{value}-$$x{value})/($$y{min}-$$x{min});
		$openprint::log->debug("Returning " . $$Object{value}) if $debug;
		return $Object;
	} # end if
	$openprint::log->debug("Returning nothing") if $debug;
	return;
} # end sub find_entry

sub add_delta_business_days {
	my ( $year, $month, $day, $delta ) = @_;

	while ($delta) {
		( $year, $month, $day ) = Date::Calc::Add_Delta_Days( $year, $month, $day, $delta > 0 ? 1 : -1 );
		while ( 6 <= Date::Calc::Day_of_Week( $year, $month, $day ) ) {
			( $year, $month, $day ) = Date::Calc::Add_Delta_Days( $year, $month, $day, $delta > 0 ? 1 : -1 );
		} # end while
		$delta -= ( $delta > 0 ? 1 : -1 );
	} # end while

	return ( $year, $month, $day );
} # end sub add_delta_business_days

sub smart_time {
	my $difference = time - $_[0];
	if ( $difference > 7*24*60*60 ) {
# Use date
		return Date::Format::time2str( '<span title="%A, %b %d %Y at %H:%M">%A, %b %d %Y</span>', $_[0] );
	} elsif ( $difference > 24*60*60 ) {
# Use date
		return Date::Format::time2str( '<span title="%A, %b %d %Y at %H:%M">%A</span>', $_[0] );
	} elsif ( $difference > 3600 ) {
# Use hours
		$difference = int($difference/3600);
		return Date::Format::time2str( '<span title="%A, %b %d %Y at %H:%M">', $_[0] ) . $difference. ' hour'.($difference==1?'':'s').' ago</span>';
	} elsif ( $difference > 60 ) {
		$difference = int($difference/60);
		return Date::Format::time2str( '<span title="%A, %b %d %Y at %H:%M">', $_[0] ) . $difference. ' minute'.($difference == 1?'':'s').' ago</span>';
	} else {
		$difference = int($difference);
		return Date::Format::time2str( '<span title="%A, %b %d %Y at %H:%M">', $_[0] ) . $difference. ' second'.($difference == 1?'':'s').' ago</span>';
	}
} # end sub smart_time

sub get_files_recursive {
	if ( ! -d $_[0] ) {
		$openprint::log->error("Supplied path $_[0] was not a directory");
		return;
	}
	my @results;
	my @filenames;
	if ( opendir DIRHANDLE, $_[0] ) {
		@filenames = readdir DIRHANDLE;
		closedir DIRHANDLE;
	} # end if
$openprint::log->debug("Have @filenames from $_[0]");
	foreach ( @filenames ) {
		next if $_ =~ /^\./;
		my $path = $_[0].'/'.$_ ;
		if ( -d $path ) {
			push @results, get_files_recursive( $path );
		} elsif ( -f $path ) {
			push @results, $path;
		} else {
			$openprint::log->debug("What was $path");
		}
	}
	return @results;
}

sub make_hash_from_array {
	my $key = shift;
	my %results;
	foreach my $object ( @_ ) {
		$results{$$object{$key}} = [] if ! $results{$$object{$key}};
		push @{$results{$$object{$key}}}, $object;
	}
	return wantarray ? %results : \%results;
}

sub compare_hash {
	my ( $a, $b ) = @_;

	return 0 if ( (!$a) and (!$b) );
	return 1 if ($a and !$b) or ( !$a and $b );

	if (%{$a} != %{$b}) {
		return 1;
	} else {
		my %cmp = map { $_ => 1 } keys %{$a};
		for my $key (keys %{$b}) {
			last unless exists $cmp{$key};
			last unless $$a{$key} eq $$b{$key};
			delete $cmp{$key};
		}
		if (%cmp) {
			return 1;
		}
		return 0
	}
} # end sub compare_hash

sub json_to_html {
	my ($input) = @_;
	my $html;
	if ( ref $input eq 'ARRAY' ) {
		$html .= '<ol>'. join("\n", map { '<li>'.json_to_html($_).'</li>' } @$input ).'</ol>';
	} elsif ( ref $input eq 'HASH' ) {
		$html .= '<table>';
		for my $k (sort keys %$input) {
			$html .= '<tr><th>'.$k.'</th><td>'.json_to_html($input->{$k}).'</td></tr>';
		}
		$html .= '</table>';
	} else {
		$html .= '<span>'.$input.'</span>';
	}
	return $html;
}

1;
__END__
