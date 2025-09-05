use strict;
package openprint::ssi;

use constant Debug => 1;

require Date::Calc;
require JSON;

# For Hash stuff
use File::Basename;

require File::Slurp;
require URI::Encode;
require URI::Escape;
require Number::Format;
require Date::Parse;
require Date::Format;
require DateTime::Format::Pg;
require DateTime::TimeZone;
require POSIX;

require ssi;
require sets;
require sql;
require openprint;
use vars qw( $r %variable %session %page_session %param %config $log $dbh );
*variable = \%openprint::variable;
*session = \%openprint::session;
*page_session = \%openprint::page_session;
*param = \%openprint::param;
*config = \%openprint::config;
*log = \$openprint::log;
*dbh = \$openprint::dbh;
*r = \$openprint::r;

my $parser = 'DateTime::Format::Pg';

#Used for resource hashed links
my %hash_cache;

#Used for writeTip
my $Glossary;

# Used for translations
my $Lexicon;

sub slurp_content {
	my ( $file ) = @_;

	if (substr($file, 0, 1) ne '/') {
		# Use a path relative to the current page
		my $path = $variable{uri};
		$path =~ s/(.*\/).*/$1/;
		$file = $path . $file;
	} # end if

	my $content = '';
	if ( -e $config{SkinPath}.$file ) {
		$content = File::Slurp::read_file($config{SkinPath}.$file, err_mode => 'carp' );
    #$openprint::log->debug("Slurping file $file from $config{SkinPath}");
    
	} elsif ( -e $config{SkinPath}.'/html/'.$file ) {
		$content = File::Slurp::read_file($config{SkinPath}.'/html/'.$file, err_mode => 'carp' );
    #$openprint::log->debug("Slurping file $file from $config{SkinPath}/html/");

	} elsif ( $ENV{DOCUMENT_ROOT} and ( -e ($ENV{DOCUMENT_ROOT}.'/openprint/'.$file) ) ) {
		$content = File::Slurp::read_file($ENV{DOCUMENT_ROOT}.'/openprint/'.$file, err_mode => 'carp' );
    #$openprint::log->debug("Slurping file $file from $ENV{DOCUMENT_ROOT}/openprint/");

    #} elsif ( $config{DOCUMENT_ROOT} and ( -e $config{DOCUMENT_ROOT}.'/openprint/'.$file ) ) {
    #$content = File::Slurp::read_file($config{DOCUMENT_ROOT}.'/openprint/'.$file, err_mode => 'carp' );
    #$openprint::log->debug("Slurping file $file from $ENV{DOCUMENT_ROOT}/html/");

	} elsif ( $ENV{DOCUMENT_ROOT} and ( -e ($ENV{DOCUMENT_ROOT}.$file) ) ) {
		$content = File::Slurp::read_file($ENV{DOCUMENT_ROOT}.$file, err_mode => 'carp' );
    #$openprint::log->debug("Slurping file $file from $ENV{DOCUMENT_ROOT}");

    #} elsif ( $config{DOCUMENT_ROOT} and ( -e $config{DOCUMENT_ROOT}.$file ) ) {
    #$content = File::Slurp::read_file($config{DOCUMENT_ROOT}.$file, err_mode => 'carp' );
	} else {
		$content = File::Slurp::read_file($file, err_mode => 'carp');
    #$openprint::log->debug("Slurping file $file");
	} # end if
	if ( ! $content ) {
		$log->warn( "No content found for $file" );
	}
	return $content;
} # end sub slurp_content

sub include {
	my ( $file, $variable ) = @_;
	$variable = \%variable if ! $variable;

	my $content = slurp_content( $file );
	return variable_substitution( \$content, $variable );
} # end sub include

#i'm adding more and more recursion in an attempt to make this faster.
# this big bottleneck is all the regexp searches through the text.
# the text is huge, so the more we break it down, the faster these get.
sub variable_substitution {
	my ( $text, $variable ) = @_;

	$variable = \%openprint::variable if ! $variable;

	my $result = '';
	my $after = $$text;

  #$log->debug("Beginning: $after");
	while ( $after ) {
    if ( $after =~ /(.*?)<!--#include\s+virtual="([^"]+)"\s*-->(.*)/si ) {
      $after = $3;
      my $before = variable_substitution(\$1, $variable);
      #$log->debug("Before include $2 $3 $before after: $after");
      #$log->debug( "Including $2");
      $result .= $before .include($2);
    } elsif ( $after =~ /(.*?)<\?\s*(.*?)\s*\?>(.*)/ms ) {
			$result .= $1;
      #$log->debug("Before $result commmand $2 after $3");
			(my $command, $after) = ( $2, $3 );
			$after =~ s/^\s+$//m;

			if ( $command =~ /^while\s*\(\s*(.*)\s*\)/ ) {
				my $condition = $1;
				if ( $after =~ /(.*?)<\?\s*endwhile\s*\(\s*\Q$condition\E\s*\)\s*\?>(.*)/si ) {
					( my $middle, $after ) = ( $1, $2 );
					while ( eval $condition ) {
						$result .= variable_substitution( \$middle, $variable );
					} # end while
					$log->error( "Eval error of ($condition), Reason: " . $@ ) if $@;
				} else {
					$log->error("Unable to find terminating while ($command)");
				} # end if
			} elsif ( $command =~ /^if\s*\(\s*(.*)\s*\)/ ) {
				my $dataname = $1;
				if ( $after =~ /(.*?)<\?\s*endif\s*\(\s*\Q$dataname\E\s*\)\s*\?>(.*)/si ) {
					( my $middle, $after ) = ( $1, $2 );
					if ( $after =~ /^\n\r?$/ ) {
						$after = '';
					} elsif ( $after =~ /^\r?\n$/ ) {
						$after = '';
					} # end if

					my $elsetext = '';

					if ( $middle =~ /(.*?)<\?\s*else\s*\(\s*\Q$dataname\E\s*\)\s*\?>(.*)/si ) {
						( $middle, $elsetext ) = ( $1, $2 );
					} # end if

					$_ = eval $dataname;
					$log->error( "Eval error of if ($dataname), Reason:" . $@ ) if $@;
					if ( $_ ) {
						$result .= variable_substitution( \$middle, $variable );
					} elsif ( $elsetext ne '' ) {
						$result .= variable_substitution( \$elsetext, $variable );
					} # end if
				} else {
					$log->error("Unable to find terminating if ( $command ) in $after");
				} # end if
			} elsif ( $command =~ /^eval\s*\(\s*(.*)\s*\)/ms ) {
				eval $1;
				$log->error("Eval error of ($1), Reason: ".$@) if $@;
			} elsif ( $command =~ /^echo\s*\(\s*(.*)\s*\)/ms ) {
				if ( !$1 ) {	
					Warning("No content in echo command $command");
				} else {
					$_ = eval $1;
					if ( $@ ) {
						$log->error("Eval error ($@) of ($1)")
					} else {
						$result .= $_;
					}
				}
			} elsif ( $command =~ /^translate\s*\(\s*([\S]+)\s*\)/ms ) {
				$result .= translate($1);
			} elsif ( $command =~ /^hash_link\s*\(\s*'?([^\s']+)'?\s*\)/ms ) {
				$result .= hash_link($1);
			} elsif ( $command =~ /^hecho\s*\(\s*(.*)\s*\)/ms ) {
				$_ = eval $1;
				$result .= html_escape($_) if $_;
				$log->error( "Eval error of ($1), Reason: " . $@ ) if $@;
			} elsif ( $command =~ /^checked\s*\(\s*(.*)\s*\)/ms ) {
				$result .= checked( eval $1 );
			} elsif ( $command =~ /^include\s*\(\s*'?([^'\)]*)'?\s*\)/ms ) {
				$result .= include( $1, $variable );
			} elsif ( $command =~ /^slurp\s*\(\s*'?([^'\)]*)'?\s*\)/ms ) {
				$result .= slurp_content( $1 );
			} else {
				if ( ! exists $$variable{$command} ) {
          $result .= ssi::eval_variable($log, $variable, $command);
					$log->debug("Unknown simple variable subsititution $command");
				} elsif ( ! defined $$variable{$command} ) {
          #$log->debug("Undefined simple variable subsititution $command");
				} else {
					$result .= $$variable{$command} if $$variable{$command};
				}
			} # end if
		} else {

# No subsititutions found, just return
			return $result.$after;
		} # end if have a command
	} # end while after
	return $result;
} # end sub variable_substitution

my %html_replacements = (
	'&'	=>	'&amp;',
	'"'	=>	'&quot;',
	'<' =>	'&lt;',
	'>' =>	'&gt;',
);
my $replacement_string = join '', keys %html_replacements;
sub html_escape {
	my $thing = $_[0];

	$thing =~ s/([\Q$replacement_string\E])/$html_replacements{$1}/g;
	return $thing;
}

sub escape_single_quotes {
	for( $_ = 0; $_ < @_; $_ += 1 ) {
		next if ! defined $_[$_];
		$_[$_] =~ s/'/\\'/mg;
	} 
	return @_;
}

sub escape_quotes {
	for( $_ = 0; $_ < @_; $_ += 1 ) {
		next if ! defined $_[$_];
		$_[$_] =~ s/"/&quot;/mg;
	} 
	return @_;
} # end sub escape_quotes

sub htmlize {
	return if ! @_;
	if ( @_ == 1 ) {
		$_ = shift;
		return if ! defined $_;
		$_ =~ s/&/&amp;/mg;
		$_ =~ s/"/&quot;/mg;
		$_ =~ s/</&lt;/mg;
		$_ =~ s/>/&gt;/mg;
		$_ =~ s/\r\n/<br\/>/mg;
		$_ =~ s/\n\r/<br\/>/mg;
		$_ =~ s/\n/<br\/>/mg;
		return $_;
	} # end if
	for( $_ = 0; $_ < @_; $_ += 1 ) {
		next if ! defined $_[$_];
		$_[$_] =~ s/&/&amp;/mg;
		$_[$_] =~ s/"/&quot;/mg;
		$_[$_] =~ s/</&lt;/mg;
		$_[$_] =~ s/>/&gt;/mg;
		$_[$_] =~ s/\r\n/<br\/>/mg;
		$_[$_] =~ s/\n\r/<br\/>/mg;
		$_[$_] =~ s/\n/<br\/>/mg;
	} # end for
	return @_;
} # end sub htmlize

sub unhtmlize {
	return if ! @_;
	if ( @_ == 1 ) {
		$_ = shift;
		return if ! defined $_;
		$_ =~ s/&amp;/&/mg;
		$_ =~ s/&quot;/"/mg;
		$_ =~ s/&lt;/</mg;
		$_ =~ s/&gt;/>/mg;
		$_ =~ s/<br\/>/\n/mg;
		return $_;
	} # end if
	for( $_ = 0; $_ < @_; $_ += 1 ) {
		next if ! defined $_[$_];
		$_[$_] =~ s/&amp;/&/mg;
		$_[$_] =~ s/&quot;/"/mg;
		$_[$_] =~ s/&lt;/</mg;
		$_[$_] =~ s/&gt;/>/mg;
		$_[$_] =~ s/<br\/>/\n/mg;
	} # end for
	return @_;
} # end sub unhtmlize

sub encode_html {
	my ( $html, $tags ) = @_;

	$html =~ s/\r\n/<br\/>/mg;
	$html =~ s/\n\r/<br\/>/mg;
	$html =~ s/\n/<br\/>/mg;
	return $html;
} # end sub encode_html

sub make_drop_down {
	require HTML::Entities;
	my ( $data, $checkval, $options ) = @_;
	$options = {} if ! $options;
	my $check_array;
	if ( ref $checkval eq 'ARRAY' ) {
		$check_array = $checkval;
	} else {
		$check_array = [ $checkval ];
	} # end if

	my %selected = map { $_ => $_ } @$check_array;

	my $html = '';
	if ( $$options{prepend} ) {
		for ( my $n = 0; $n < @{$$options{prepend}}; $n += 2 ) {
			$html .= join('', 
        '<option value="',
					( $$options{encode} ? HTML::Entities::encode_entities(Encode::encode('utf-8',$$options{prepend}[$n])) : $$options{prepend}[$n] ),
      '"',
					( $selected{ $$options{prepend}[$n] } ? ' selected="selected"' : '' ),
      '>',
					( $$options{encode} ? HTML::Entities::encode_entities( Encode::encode('utf-8',$$options{length} ? substr($$options{prepend}[$n + 1],0, $$options{length}) : $$options{prepend}[$n + 1] ) ) : $$options{length} ? substr($$options{prepend}[$n + 1],0, $$options{length}) : $$options{prepend}[$n + 1] ),
      '</option>',"\n",
					);
		} # end for
	} # end if

  for (my $i = 0; $i < @{$data}; $i++) {
    my $value;
    my $label;
    if ( ref $$data[$i] eq 'ARRAY' ) {
      my $row = $$data[$i];
      $value = $$row[0];
      $label = $$row[1];
    } else {
      $value = $$data[$i];
      $i++;
      $label = $$data[$i];
    }
  
    if ($$options{length}) {
      $label = substr($label,0, $$options{length});
    }
    if ($$options{encode}) {
      $value = HTML::Entities::encode_entities(Encode::encode('utf-8', $value));
      $label = HTML::Entities::encode_entities(Encode::encode('utf-8', $label));
    }
		
		$html .= join('','<option value="', $value, '"', ( $selected{ $value } ? ' selected="selected"' : '' ), '>', $label, '</option>', "\n");
	} # end for

	if ( $$options{append} ) {
		for ( my $n = 0; $n < @{$$options{append}}; $n += 2 ) {
      $html .= join('',
        '<option value="',
        ( $$options{encode} ? HTML::Entities::encode_entities(Encode::encode('utf-8',$$options{append}[$n])) : $$options{append}[$n] ),
        '"',
        ( $selected{ $$options{append}[$n] } ? ' selected="selected"' : '' ),
        '>',
        ( $$options{encode} ? HTML::Entities::encode_entities( Encode::encode('utf-8',$$options{length} ? substr($$options{append}[$n + 1],0, $$options{length}) : $$options{append}[$n + 1] ) ) : $$options{length} ? substr($$options{append}[$n + 1],0, $$options{length}) : $$options{append}[$n + 1] ),
        '</option>',"\n",
      );
		} # end for
	} # end if
	return $html;
} # sub make_drop_down

sub fill_drop_down {
	my ( $log, $dbh, $search, $checkval, $length ) = @_;
	my ( $temp, @search_data, $n, $checked);

	@search_data = sql::execute( $log, $dbh, $search );

	return make_drop_down( \@search_data, $checkval, $length );
} # sub customer_drop_down

sub fill_select {
	my ( $log, $dbh, $search, $length, @checkarray ) = @_;
	my @search_data = sql::execute( $log, $dbh, $search );
	return make_drop_down( \@search_data, \@checkarray, $length );
} # sub customer_drop_down

sub return_states_and_provinces {
  my $selected_country = shift;
  my $selected_state = shift;
	require provinces;
	require states;
	my @states_and_provinces = ();
	push @states_and_provinces, @states::states if (!$selected_country) or ($selected_country eq 'US');
	push @states_and_provinces, @provinces::provinces if !$selected_country or ($selected_country eq 'CA');

	return make_drop_down(\@states_and_provinces, $selected_state);
} # end sub return_states_and_provinces

sub return_states {
	require states;
	return make_drop_down( \@states::states, shift );
} # end sub return_states

sub return_provinces {
	require provinces;
	return make_drop_down( \@provinces::provinces, shift );
} # end sub return_provinces

sub return_countries {
	require countries;
	return make_drop_down( \@countries::countries, [@_] );
} # end sub return_countries

sub return_years {
	my ( $start, $end, $selected ) = @_;
	$start = $openprint::config{startYear} if ! $start;
	$end = (localtime(time))[5] + 1901 if ! $end;
	#$selected = (localtime(time))[5] + 1900 if ! defined $selected;
#$log->debug("sub return_years $start .. $end $selected");
	return make_drop_down( [ map { $_, $_ } ( $start .. $end ) ], $selected );
} # end sub return_years

sub getyears {
	my ( $startyear, $numyears, $selected ) = @_;
	my $years = '';

	$selected = (localtime(time))[5] + 1900 if ! defined $selected;
	$numyears = 5 if ! $numyears;

	for ( my $year = $startyear; $year < $startyear + $numyears; $year += 1 ) {
		$years .= "<option value=\"$year\" " . ($selected == $year ? 'selected="selected"' : "" ) .">$year</option>\n";
	} # end for

	return $years;
} # end sub getyears

sub getmonths {
	my @months = map { $_, Date::Calc::Month_to_Text( $_ ) } ( 1 .. 12 );
	my $selected = shift;
	if ( $selected ) {
		$selected = int($selected);
	#} elsif ( ! defined $selected ) {
		#$selected = (localtime(time))[4]+1;
	} # end if
	return make_drop_down( \@months, $selected );
} # edn sub getmonths

sub getdays {
	my ( $selected, $year, $month ) = @_;
	my $maxdays = 31;
	if ( $year and $month and ( $maxdays > Date::Calc::Days_in_Month( $year, $month ) ) ) {
		$maxdays = Date::Calc::Days_in_Month( $year, $month );
	} # en dif
	my @days = map { $_, $_ } ( 1 .. $maxdays );
	$selected = int($selected);
	$selected = (localtime(time))[3] if ! defined $selected;
	return make_drop_down( \@days, $selected );
} # end sub getdays

sub getemployee_numbers {
	my ( $r, $log, $dbh, $selected ) = @_;
	my ( $temp, $employees );

	my @results = sql::execute( $log, $dbh, 'SELECT * FROM EmployeeNumbers' );
	for ( my $index = 0; $index < @results; $index += 3 ) {
		if ( $results[$index] eq $selected ) {
			$employees .= "<option value=\"$results[$index]\" selected=\"selected\">";
		} else {
			$employees .= "<option value=\"$results[$index]\">";
		} # end if

		$employees .= get_range_text($results[$index+1],$results[$index+2]);
		$employees .= "</option>\n";
	} #end for

	return $employees;
}

sub getannual_sales {
	my ( $r, $log, $dbh, $selected ) = @_;
	my ( $temp, $employees );

	my @results = sql::execute( $log, $dbh, "SELECT ID,Min,Max FROM AnnualSales ORDER BY Id" );
	for ( my $index = 0; $index < @results; $index += 3 ) {
		if ( $results[$index] eq $selected ) {
			$employees .= "<option value=\"$results[$index]\" selected>";
		} else {
			$employees .= "<option value=\"$results[$index]\">";
		} # end if
		
		$employees .= get_range_text($results[$index+1],$results[$index+2]);
		$employees .= "</option>\n";
	} #end for

	return $employees;
} # end sub getannual_sales

sub get_range_text {
	my ( $min, $max ) = @_;
	my $text = '';

	if ( $min eq '' ) {
		$text = 'Under '
	} else {
		$text = $min;
	} # end if
	if ( $max eq '' ) {
		$text .= ' or more';
	} else {
		$text .= ' - ' if $min ne '';
		$text .= $max;
	} # end if
	return $text;
} # end sub get_range_text

sub fix_date {
	my ( $year, $month, $day ) = @_;
	$month = int $month;
	$month = 12 if ( $month > 12 );
	$month = 1 if $month < 0;
	if ( $year and $month and $day > Date::Calc::Days_in_Month( $year, $month ) ) {
		$day = Date::Calc::Days_in_Month( $year, $month );
	} # end if
	return ( $year, $month, $day );
} # end sub fix_date

sub fix_datetime {
	my ( $year, $month, $day, $hour,$minute,$second ) = @_;
	$month = int $month;
	$month = 12 if ( $month > 12 );
	$month = 1 if $month < 0;
	if ( $year and $month and $day > Date::Calc::Days_in_Month( $year, $month ) ) {
		$day = Date::Calc::Days_in_Month( $year, $month );
	} # end if
  $hour = 23 if $hour > 23;
  $minute = 59 if $minute > 59;
  $second = 59 if $second > 59;
	return ( $year, $month, $day, $hour, $minute, $second );
} # end sub fix_datetime

sub get_dates {
	my ( $log, $dbh, $year, $month, $day ) = @_;

	( $year, $month, $day ) = fix_date( int $year, int $month, int $day );

	my ( $startYear ) = $openprint::config{startYear};
	$startYear = 2002 if ! $startYear;

	return (
			getyears( $startYear, (localtime(time))[5]-100, $year ),
			getmonths($month),
			getdays($day, $year, $month ),
			$year ? join('-', $year, $month, $day ) : undef,
			);
}

sub get_start_end_dates {
	my ( $log, $dbh, $variable, $startYear, $startMonth, $startDay, $endYear, $endMonth, $endDay ) = @_;

	my $start;
	( $start ) = $openprint::config{startYear};
	$start = 2002 if ! $start;
	if ( ! $startYear ) {
		$startYear = (localtime(time))[5]+1900;
	} # end if

	$startMonth = $startMonth ? $startMonth : (localtime(time))[4]+1;
	$endYear = $endYear ? $endYear : (localtime(time))[5]+1900;
	$endMonth = $endMonth ? $endMonth : (localtime(time))[4]+1;

	if ( $startDay > Date::Calc::Days_in_Month( $startYear, $startMonth ) ) {
		$startDay = Date::Calc::Days_in_Month( $startYear, $startMonth );
	} # end if
	if ( $endDay > Date::Calc::Days_in_Month( $endYear, $endMonth ) ) {
		$endDay = Date::Calc::Days_in_Month( $endYear, $endMonth );
	} # end if

	$$variable{ddmStartYear} = $$variable{startyears} = getyears( $start, (localtime(time))[5]-100, $startYear );
	$$variable{ddmEndYear} = $$variable{endyears} = getyears( $start, (localtime(time))[5]-100, $endYear );
	$$variable{ddmStartMonth} = $$variable{startmonths} = getmonths($startMonth);
	$$variable{ddmEndMonth} = $$variable{endmonths} = getmonths($endMonth);
	$$variable{ddmStartDay} = $$variable{startdays} = getdays($startDay);
	$$variable{ddmEndDay} = $$variable{enddays} = getdays($endDay ? $endDay : (localtime(time))[3]);

	$$variable{StartDate} = join( '-', $startYear, $startMonth, ( $startDay ? $startDay : 1 ) );
	$$variable{EndDate} = join( '-', $endYear, $endMonth, ( $endDay ? $endDay : (localtime(time))[3] ) );

} # end sub get_start_end_dates

sub button {
	my ( $name, $options ) = @_;

	if ( $$options{href} ) {
		my ( $href ) = $$options{href} =~ /^([^\?]+)/;
		if ( ! ( $href =~ /^\// ) ) {
# Use a path relative to the current page
			my $path = $variable{uri};
			$path =~ s/(.*\/).*/$1/;
			$href = $path . $href;
		} # end if
		my $PageSetting = openprint::Page_Setting::get($href);
		return if $PageSetting and ! $PageSetting->can_view();
    if ( ! $$options{onclick} ) {
      $$options{onclick} = 'window.location.href=\''.$$options{href}.'\';return false;';
      delete $$options{href};
      $$options{type} = 'button';
    }
  } elsif ( ! $$options{type} ) {
    # Default non-a types to a button
    $$options{type} = 'button';
	} # end if
	$$options{text} = $$options{value} if ! exists $$options{text} and $$options{value};
	$$options{text} = $name if ! exists $$options{text};
  if ( $$options{text} and ! $$options{value}) {
    $$options{value} = $$options{text};
  }
	my $html = 
		qq`<button id="Button$name" name="`.($$options{name} ? $$options{name} : $name).qq`" class="btn button $$options{class}" `;
    delete $$options{class};
    delete $$options{name};
	if ( $$options{href} and $$options{type} ) {
		$html .= qq`onclick="window.location='$$options{href}'" `;
    #} elsif ( $$options{onclick} and ! $$options{disabled} ) {
    #$html .= 'onclick="';
    #$html .= $$options{onclick}."return false;\" ";
	} # end if
	#$html .= "onmouseover=\"if ( typeof(btnOn) == 'function' ) { btnOn('Button$name');}\" onmouseout=\"if ( typeof(btnOff) == 'function' ) { btnOff('Button$name');}\"";
  $html .= join(' ', map { ($_ eq 'onclick' or $_ eq 'text') ? () : $_.'="'.$$options{$_}.'"' } ( keys %{$options} ) );
	$html .= '>';
	if ( $$options{image} ) {
		if ( $openprint::config{ButtonsUseImages} and ($openprint::config{ButtonsUseImages} eq 'true') ) {
			$html .= "<img src=\"/images/buttons/off/$$options{image}\" id=\"ButtonImage$name\"";
		} else {
			$html .= "<img src=\"$$options{image}\" id=\"ButtonImage$name\"";
		} # end if
		if ( $$options{title} ) {
			$html .= " alt=\"$$options{title}\"";
		} # end if
		$html .= '/>';
		if ( $$options{text} ) {
			$html .= $$options{text};
      delete $$options{text};
		} # end if
    delete $$options{image};
    #} elsif ( $openprint::config{SimpleButtons} and $openprint::config{SimpleButtons} eq 'Y' ) {
    #$html .= '<span class="l"></span><span class="c" id="'.$name.'c"' . ( $$options{title} ? ' title="'.$$options{title}.'"' : '' ) .'>' . $$options{text} .'</span><span class="r"></span>';
	} else {
		$html .= $$options{text};
	}
	$html .= $$options{type} ? '</button>
' : '</a>
';
  if ( $$options{onclick} ) {
    $html .= '<script'.($config{CSP_NONCE}?' nonce="'.$config{CSP_NONCE}.'"':'').">
    document.getElementById('Button$name').onclick = function(){
    $$options{onclick};
    };
    </script>
    ";
    delete $$options{onclick};
  } # end if

	return $html;
} # end sub button

sub writeButton {
	my ( $log, $dbh, $name, $gif, $onclick, $href, $text, $options ) = @_;
	if ( $href eq '' ) {
		$href='#';
	} # end if
	my $html = qq`<a id="Button$name" href="$href" class="button $$options{class}" `;
	if ( $onclick ne '' ) {
		$html .= 'onclick="';
		if ( ( $openprint::config{ButtonsUseImages} and ($openprint::config{ButtonsUseImages} eq 'true') ) and $gif ) {
			$html .= "btnOff('$name');";
		} # end if
		$html .= $onclick."return false;\" ";
	} # end if
	#$html .= "onmouseover=\"if ( typeof(btnOn) == 'function' ) { btnOn('Button$name');}\" onmouseout=\"if ( typeof(btnOff) == 'function' ) { btnOff('Button$name');}\"";
	$html .= '>';
	if ( ( $openprint::config{ButtonsUseImages} and ($openprint::config{ButtonsUseImages} eq 'true') ) and $gif ) {
		$html .= "<img src=\"/images/buttons/off/$gif\" name=\"Button$name\"";
		if ( $text ne '' ) {
			$html .= "alt=\"$text\"";
		} # end if
		$html .= "/>";
	} else {
		$html .= '<span class="l"></span><span class="c" id="'.$name.'c">' . $text .'</span><span class="r"></span>';
	}
	$html .= '</a>';
	return $html;
} # end sub writeButton

sub checked {
	if ( $_[0] ) {
		return 'checked="checked"';
	} # end if
	return '';
} # end sub checked

sub writeTip {
	my $word = shift;
	if ( ! defined $Glossary ) {
		%$Glossary = sql::execute( undef, undef, 'SELECT word, definition FROM Glossary' );
	} # end if
	if ( $$Glossary{$word} ) {
		return sprintf(q`<span class="TipLink" onmouseover="tipOn('%1$s',3,event);" onmouseout="tipOff('%1$s');">%1$s</span>`, $word );
	} else {
		return $word;
	} # endif
} # end  sub writeTip

sub setup_datetime_select {
	my ( $page, $prefix, $delta_seconds ) = @_;

  my @fields = ( 'year','month','day','hour','minute','second');
	if ( ( 
        ! ( 
          exists $session{$page.'?'.$prefix.'_year'}
          and
          exists $session{$page.'?'.$prefix.'_month'}
          and 
          exists $session{$page.'?'.$prefix.'_day'} ) )
      or ( time - $session{$page.'?lastupdated'} > 3600 ) ) {
		if ( $delta_seconds ne '' ) {
      my $dt = DateTime->now( time_zone=>$openprint::TZ );
      $dt = $dt->add(seconds=>$delta_seconds);

      @session{map {$page.'?'.$prefix.'_'.$_} @fields} = map { $dt->$_() } @fields;
    } else {
      @session{map {$page.'?'.$prefix.'_'.$_} @fields} = map { '' } @fields;
		} # end if
	} else {
      @session{map {$page.'?'.$prefix.'_'.$_} @fields} = fix_datetime(
      @session{map {$page.'?'.$prefix.'_'.$_} @fields} );
	} # end if
} # end sub setup_datetime_select

sub setup_date_select {
	my ( $page, $prefix, $delta ) = @_;
	if ( ( ! ( exists $session{$page.'?'.$prefix.'_year'} and exists $session{$page.'?'.$prefix.'_month'} and exists $session{$page.'?'.$prefix.'_day'} ) ) or ( time - $session{$page.'?lastupdated'} > 3600 ) ) {
		if ( $delta ne '' ) {
			@session{$page.'?'.$prefix.'_year',$page.'?'.$prefix.'_month',$page.'?'.$prefix.'_day'} = Date::Calc::Add_Delta_Days( Date::Calc::Today(), 1*$delta );
		} else {
			@session{$page.'?'.$prefix.'_year',$page.'?'.$prefix.'_month',$page.'?'.$prefix.'_day'} = ( '', '', '' );
		} # end if
	} else {
		@session{$page.'?'.$prefix.'_year',$page.'?'.$prefix.'_month',$page.'?'.$prefix.'_day'} = fix_date( @session{$page.'?'.$prefix.'_year',$page.'?'.$prefix.'_month',$page.'?'.$prefix.'_day'} );
	} # end if
} # end sub setup_date_select

sub date_select {
	my ( $prefix, $value, $options ) = @_;

	my ( $year,$month,$day );
	if ( ref $value eq 'ARRAY' ) {
		( $year, $month, $day ) = @$value;
	} elsif ( $value eq ' ' ) {
		( $year, $month, $day ) = ( '', '', '' );
	} else {
		( $year, $month, $day ) = split('-', $value );
	} # end if
	if ( ref $options eq 'HASH' ) {
	} elsif ( $options ) {
    $openprint::log->error("deprecated use of options in daet_select");
		$options = {onchange=>$options};
	} # end if
#$openprint::log->debug(" date_select: $value : ($year,$month,$day), order: $$options{order}");
	$$options{order} = 'y,m,d' if ! $$options{order};
	my @fields;
	if ( $$options{fields} ) {
		@fields = split(',', $$options{fields} );
	} 
	
	my ( $start_year, $start_month, $start_day ) = split( '-', $$options{start} ) if $$options{start};
	my ( $end_year, $end_month, $end_day ) = split( '-', $$options{end} ) if $$options{end};

	my $class = 'DateSelector';
	$class .= 'C' if $$options{with_clear};
	$class .= 'T' if $$options{with_today};

	my $html = '<span class="'.$class.'" id="'.$prefix.'_date">
';
	foreach my $o ( split(',', $$options{order}) ) {
		if ( ( $o eq 'y' ) and ( (!@fields) or sets::isin('year', \@fields) ) ) {
			$html .= sprintf(q`<select id="%1$s_year" name="%1$s_year" onchange="setDaysDropDown(this.value,this.form.elements['%1$s_month'].value,this.form.elements['%1$s_day'],this.form.elements['%1$s_day'].value);%2$s"`, $prefix, $$options{onchange} );
      $html .= ' on_change_this="'.$$options{on_change_this}.'"' if $$options{on_change_this};
      $html .= '><option value=""> </option>';
			$html .= return_years( $start_year, $end_year, $year );
			$html .= '</select>'."\n";
#$log->debug($html);
		} elsif ( ( $o eq 'm' ) and ( (!@fields) or sets::isin('month', \@fields) ) ) {
			$html .= sprintf(q`<select id="%1$s_month" name="%1$s_month" onfocus="this.previousValue=this.value" onchange="setDaysDropDown(this.form.elements['%1$s_year'].value,this.value,this.form.elements['%1$s_day'],this.form.elements['%1$s_day'].value, this.previousValue);%2$s;this.previousValue=this.value;"`, $prefix, $$options{onchange} );
      $html .= ' on_change_this="'.$$options{on_change_this}.'"' if $$options{on_change_this};
      $html .= '><option value=""> </option>';
			$html .= getmonths( $month );
			$html .= '</select>'."\n";
#$log->debug($html);
		} elsif ( ( $o eq 'd' ) and ( (!@fields) or sets::isin('day', \@fields) ) ) {
			$html .= sprintf('<select id="%1$s_day" name="%1$s_day" onchange="%2$s"', $prefix, $$options{onchange} );
      $html .= ' on_change_this="'.$$options{on_change_this}.'"' if $$options{on_change_this};
      $html .= '><option value=""> </option>';
			$html .= getdays( $day, int($year), int($month) );
			$html .= '</select>'."\n";
#$log->debug($html);
		} # endif
	} # end foreach o
  $html .= "\n";
	if ( $$options{with_clear} ) {
		$html .= button( $prefix.'_clear', {
				#onclick=>q`date_clear( $('`.$prefix.q`_year'), $('`.$prefix.q`_month'), $('`.$prefix.q`_day') );`.$$options{onchange},
				on_click_this=>'clear_date', data_prefix=>$prefix,
				text=>'C', title=>'Clear', class=>'Clear',
				} );
	} # end if
	if ( $$options{with_today} ) {
		$html .= button( $prefix.'_today', {
        on_click_this=>'new_set_today', data_prefix=>$prefix,
				#onclick=>q`set_today( $('`.$prefix.q`_year'), $('`.$prefix.q`_month'), $('`.$prefix.q`_day') );`.$$options{onchange},
				text=>'T', title=>'Today', class=>'Today',
				} );
	} # end if
	$html .= '<span id="'.$prefix.'_alert"></span>
</span>';
	return $html;
} # end sub date_select

sub date_select_session {
	my ( $page, $prefix, $options ) = @_;
	return date_select( $prefix, [ @session{$page.'?'.$prefix.'_year',$page.'?'.$prefix.'_month',$page.'?'.$prefix.'_day'} ], $options );
} # end sub date_select_session

sub datetime_select_session {
	my ( $page, $prefix, $options ) = @_;
	return datetime_select( $prefix, [ @session{
			$page.'?'.$prefix.'_year',
			$page.'?'.$prefix.'_month',
			$page.'?'.$prefix.'_day',
			$page.'?'.$prefix.'_hour',
			$page.'?'.$prefix.'_minute'} ], $options );
} # end sub date_select_session

sub datetime_select {
	my ( $prefix, $value, $options ) = @_;

	my ($year,$month,$day, $hour,$min,$sec);
	if ( ! defined $value ) {
		($year,$month,$day, $hour,$min,$sec) = Date::Calc::Localtime( time );
	} elsif ( ref $value eq 'ARRAY' ) {
		($year,$month,$day, $hour,$min,$sec) = @$value;
	} elsif ( $value ) {
		($year,$month,$day, $hour,$min,$sec) = Date::Calc::Localtime( Date::Parse::str2time( $value ) );
		if ( ! $year ) {
$openprint::log->error("No date from $value");
		}
	} else {
		$year = '';
		$month = '';
	} # end if
#$openprint::log->debug("$year,$month,$day, $hour:$min:$sec");

	if ( ref $options eq 'HASH' ) {
	} elsif ( $options ) {
		$_ = $options;
		$options = {};
		$$options{onchange} = $_;
	} # end if
#$openprint::log->debug(" date_select: $value : ($year,$month,$day), order: $$options{order}");
	$$options{order} = 'y,m,d' if ! $$options{order};

	my $class = 'DateTimeSelector';
	$class .= 'C' if $$options{with_clear};
	$class .= 'T' if $$options{with_today};

	my $html = '<span class="'.$class.'">';
	$html .= sprintf(q`<span id="%1$s_date"><select id="%1$s_year" name="%1$s_year" onchange="setDaysDropDown(this.value,this.form.elements['%1$s_month'].value,this.form.elements['%1$s_day'],this.form.elements['%1$s_day'].value);%2$s">
`, $prefix, $$options{onchange} );
	$html .= '<option value=""> </option>';
	$html .= return_years( undef, undef, $year );
	$html .= '</select>
';
	$html .= sprintf(q`<select id="%1$s_month" name="%1$s_month" onfocus="this.previousValue=this.value;" onchange="setDaysDropDown(this.form.elements['%1$s_year'].value,this.value,this.form.elements['%1$s_day'],this.form.elements['%1$s_day'].value,this.previousValue);this.previousValue=this.value;%2$s">`, $prefix, $$options{onchange} );
	$html .= '<option value=""> </option>';
	$html .= getmonths( $month );
	$html .= '</select>
';
	$html .= sprintf('<select id="%1$s_day" name="%1$s_day" onchange="%2$s">', $prefix, $$options{onchange} );
	$html .= '<option value=""> </option>';
	$html .= getdays( $day, $year, $month );
	$html .= '</select></span>
';
	$html .= sprintf('<span id="%1$s_time" class="time"%3$s>
<select id="%1$s_hour" name="%1$s_hour" onchange="%2$s"><option value=""></option>%4$s</select> :
	<select id="%1$s_minute" name="%1$s_minute" onchange="%2$s">
	<option value=""> </option>%5$s
	</select></span>', $prefix, $$options{onchange}, 
		( ( exists $$options{with_time} and ! $$options{with_time} ) ? ' style="display: none;"' : '' ),
		make_drop_down( [ map { $_, $_ } ( 0 .. 23 ) ], $hour ),
		make_drop_down( [ map { (sprintf('%.2d', $_)) x 2 } ( 0 .. 59 ) ], $min ),
	);
  $html .= "\n";
	if ( $$options{with_clear} ) {
		$html .= button( $prefix.'_clear', { onclick=>q`date_clear( $('`.$prefix.q`_year'), $('`.$prefix.q`_month'), $('`.$prefix.q`_day') );`.$$options{onchange}, text=>'C' } )."\n";
	} # end if
	if ( $$options{with_today} ) {
		$html .= button( $prefix.'_today', { 'onclick'=>sprintf(q`set_today( $('%1$s_year'), $('%1$s_month'), $('%1$s_day'), $('%1$s_hour'), $('%1$s_minute') );`, $prefix ).$$options{onchange}, text=>'T' } )."\n";
	} # end if
	$html .= '<span id="'.$prefix.'_alert"></span></span>';
	return $html;
} # end sub datetime_select

sub datetime_text {
	 my ( $prefix, $value, $onchange ) = @_;

	 my ($year,$month,$day, $hour,$min,$sec) = Date::Calc::Localtime( $value ? Date::Parse::str2time( $value ) : time );
#$openprint::log->debug("$year,$month,$day, $hour:$min:$sec");

	 my $html = '';
	 $html .= sprintf('<span id="%1$s_year">%2$.4d</span>-<span id="%1$s_month">%3$.2d</span>-<span id="%1$s_day">%4$.2d</span> <span id="%1$s_hour">%5$.2d</span>:<span id="%1$s_minute">%6$.2d</span>', $prefix, $year, $month, $day, $hour, $month );
	 return $html;
} # end sub datetime_text

sub save_params {
	my ( $url, @keys ) = @_;
  return if !%param;

	foreach ( @keys ) {
		$openprint::log->debug('save_params: key '.$_) if Debug;
		if (!exists $param{$_}) {
			$openprint::log->debug('save_params: does not exist in param key '.$_) if Debug;
      #undef($session{$url.'?'.$_});
			next;
		}
		if (ref $param{$_} eq 'ARRAY') {
			$page_session{$_} = $session{"$url?$_"} = join(',', @{$param{$_}} );
$openprint::log->debug("Storing ARRAY ($_) (".$session{"$url?$_"}.")") if Debug;
		} else {
      s/^\s+//, s/\s+$// for $param{$_};
			$page_session{$_} = $session{$url.'?'.$_} = $param{$_};
$openprint::log->debug("Storing ($_) (".$session{"$url?$_"}.")") if Debug;
		} # end if
		$session{$url.'?lastupdated'} = time;
	} # end foreach
} # end sub save_params

sub boolean_override {
	my ( $for, $value, $locked_js, $unlocked_js ) = @_;
	return sprintf(q`<input type="hidden" id="%1$s" name="%1$s" value="%2$s"/><img class="Override" src="/images/%3$s.gif" onclick="var e=$('%1$s');if(e.value!='0'){e.value='0';this.src='/images/unlocked.gif';%5$s} else {e.value='1';this.src='/images/locked.gif';%4$s}" alt=""/>`, 
			$for, 1*$value, ($value ? 'locked' : 'unlocked'), $locked_js, $unlocked_js );
}
sub write_override {
	my ( $for, $value, $locked_js, $unlocked_js, $employee_only ) = @_;
	if ( 1 ) {
    my $html = sprintf('<input type="hidden" id="%1$s" name="%1$s" value="%2$s"/>', $for, ((defined($value) and sets::isin($value, ['Y', '1' ]) ) ? 'Y' : '' ));
    if ((!$employee_only) or ($session{user_type} eq 'E' or $session{user_type} eq 'A')) {
      $html .= sprintf(q`<img class="Override" src="/images/%3$s.gif" onclick="var e=$('%1$s');if(e.value){e.value='';this.src='/images/unlocked.gif';%5$s} else {e.value='Y';this.src='/images/locked.gif';%4$s}" alt="" title="Click to override"/>`, 
				$for,
				((defined($value) and sets::isin($value, ['Y', '1' ]) ) ? 'Y' : '' ),
				((defined($value) and sets::isin($value, ['Y', '1' ])) ? 'locked' : 'unlocked'),
				$locked_js, $unlocked_js );
    } else {
      #$html .= (defined($value) and sets::isin($value, ['Y', '1'])) ? 'locked' : 'unlocked';
    }
    return $html;
	} else {
		return sprintf('<input type="checkbox" id="%1$s" name="%1$s" value="%2$s" onclick="if(!this.checked){%5$s}else{%4$s};" %3$s /> <label class="radio" for="%1$s">Override</label>', $for, $value, ssi::checked( $value eq 'Y' ), $locked_js, $unlocked_js );
	} # end if
} # end sub write_override

sub count_lines {
	if ( $_[0] ) {
		my @lines = split( "\n", $_[0] );
		my $lines = scalar @lines;
		if ( $_[1] and $_[1]{width} ) {
				foreach ( @lines ) {
					$lines += ( POSIX::ceil( length($_ ) / $_[1]{width} ) ) - 1;
				}
		}	
		return $lines;
	} else {
		return 2;
	} # end if
} # end sub count_lines

sub radio {
	my ( $name, $values, $selected, $options ) = @_;

  $options = {} if !$options;

  my $id = exists($$options{id}) ? $$options{id} : '';
  delete $$options{id};
  my $container = exists $$options{container} ? $$options{container} : undef;

	my $html;
	if ( exists($$options{default}) and ! defined($selected) ) {
#$log->debug("Selecting default $$options{default} for radio $name");
		$selected = $$options{default};
    delete $$options{default};
	} # end if

  for (my $i = 0; $i < @{$values}; $i += 2) {
    my ($value, $label) = ( $$values[$i], $$values[$i+1] );
		$html .= $$container[0] if $container;
		$html .= sprintf(q`
      <div class="form-check%7$s">
				<label class="form-check-label radio%7$s" for="%1$s%6$s%2$s">
				<input class="form-check-input" type="radio" name="%1$s" value="%2$s" id="%1$s%6$s%2$s" %4$s %5$s />
				%3$s</label></div>
				`, $name, $value, $label, checked($value eq $selected),
				join(' ', map { $_.'="'.$$options{$_}.'"' } keys %{$options}),
				$id,
				( ($$options{inline} or ! exists $$options{inline} ) ? '-inline' : '' ),
				);
		$html .= $$container[1] if $container;
	} # end foreach value
	return $html;
} # end sub radio

sub checkboxes {
	my ( $name, $values, $selected, $options ) = @_;

	my $onclick = $$options{onclick} if $options;
	my $html;
	my @container = @{$$options{container}} if $$options{container};

	if ( ! $values ) {
		$values = ['on', '' ];
	} elsif ( ref $values ne 'ARRAY' ) {
		$values = [ $values ];
	}
	my $id = $$options{id} ? $$options{id} : $name;

	while ( my ( $value, $label ) = splice @{$values}, 0, 2 ) {
		$html .= $container[0] if @container;
		if ( $label ) {
			$html .= sprintf(
'
<label class="radio%7$s" for="%1$s%2$s">
<input type="checkbox" name="%1$s" value="%2$s" id="%3$s%2$s" %4$s%5$s/>
%6$s
</label>
', $name, $value, $id, checked( sets::isin( $value, $selected ) ),
( $onclick ? ' onclick="'.$onclick.'"' : ''),
$label,
( $$options{inline} ? '-inline' : '' ),
 );
		} else {
			$html .= sprintf('<input type="checkbox" name="%1$s" value="%2$s" id="%3$s%2$s" %4$s%5$s/>',
					$name, $value, $id,
					checked( sets::isin( $value, $selected ) ),
					( $onclick ? ' onclick="'.$onclick.'"' : ''), );
		} # end if has label content
		$html .= $container[1] if @container;
	} # end foreach value
	return $html;
} # end sub checkboxes

sub date {
	my ( $field, $hash ) = @_;
	$hash = \%openprint::session if ! $hash;
	return @$hash{$field.'_year',$field.'_month',$field.'_day'};
}

sub date_filter {
	my ( $field, $sql_field, $hash ) = @_;
	$sql_field = $field if ! $sql_field;
	if ( ! $hash ) {
		$hash = \%openprint::session;
		#$log->debug('ssi::date_filter: using session for hash');
	} # end if
		#foreach my $k ( keys %$hash ) {
			#$log->debug("ssi::date_filter hash{$k} => $$hash{$k}");
		#} # end foreach
	if ( ! ( $$hash{$field.'_year'} and $$hash{$field.'_month'} and $$hash{$field.'_day'} ) ) {
#$log->debug("ssi::date_filter: No date specified for $field");
		return ();
	} # end if
	my ( $year, $month, $day, $hour, $minute, $second ) = @$hash{map { $field.$_ } ( '_year','_month','_day','_hour','_minute','_second' )};
#$log->debug("ssi::date_filter: $year-$month-$day $hour:$minute:$second");
	if ( $field =~ /end$/ ) {
		$hour = 23 if ( ! defined $hour ) or $hour eq '';
		$minute = 59 if ( ! defined $minute ) or $minute eq '';
		$second = 59 if ( ! defined $second ) or $second eq '';
	} else {
		$hour = 0 if ( ! defined $hour ) or $hour eq '';
		$minute = 0 if ( ! defined $minute ) or $minute eq '';
		$second = 0 if ( ! defined $second ) or $second eq '';
	} # end if
#$log->debug("ssi::date_filter: $year-$month-$day $hour:$minute:$second");

	my $TZ = DateTime::TimeZone->new( name => $openprint::config{Timezone} );
	my $datetime = DateTime->new( time_zone => $TZ,
			( year => $year, month=>$month, day=>$day, hour=>$hour, minute=>$minute, second=>$second )
			);

	return ( $sql_field, $parser->format_datetime( $datetime ) );
} # end sub date_filter

my @input_options = ( 'type','name','id','onblur','onfocus','onkeyup','onkeypress', 'onkeydown','onchange','class','pattern','ontouch','min','max', 'step', 'placeholder', 'oninput', 'title', 'decimalplaces', 'style', 'data_on_input','data-on-input', 'data_oninput_this', 'on_input_this' );

sub input {
	my %options = @_;
	my $html = '<input';
	if ( $options{type} eq 'cardinal' ) {
		$options{step} = '1' if ! exists $options{step};
		if ( $ENV{HTTP_USER_AGENT} =~ /ip(ad|od|hone)/i ) {
			$options{type} = 'text';
			$options{pattern} = '[0-9]*' if ! $options{pattern};
		#} elsif ( $ENV{HTTP_USER_AGENT} =~ /Firefox/ ) {
			#$options{type} = 'text';
			#$options{pattern} = '[0-9]*' if ! $options{pattern};
			#delete $options{step};
		} else {
			$options{type} = 'number';
		} # end if
		$options{filter} = 'cardinalize(this);' if ! $options{filter};
		$options{oninput} = $options{filter}.$options{oninput};
		#$options{oninput} = 'this.onkeyup.call(this);' if ! $options{oninput};
	} elsif ( $options{type} eq 'integer' ) {
		$options{step} = '1' if ! exists $options{step};
		if ( $ENV{HTTP_USER_AGENT} =~ /ip(ad|od|hone)/i ) {
			$options{type} = 'text';
			$options{pattern} = '^-?\d*' if ! $options{pattern};
		#} elsif ( $ENV{HTTP_USER_AGENT} =~ /Firefox/ ) {
			#$options{type} = 'text';
			#$options{pattern} = '^-?\d*' if ! $options{pattern};
			#delete $options{step};
		} else {
			$options{type} = 'number';
		} # end if
		$options{oninput} = 'integerize(this);'.$options{oninput};
	} elsif ( $options{type} eq 'float' ) {
#$log->debug("USer agent: $ENV{HTTP_USER_AGENT}");
		$options{step} = 'any' if ! exists $options{step};
		if ( $ENV{HTTP_USER_AGENT} =~ /ip(ad|od|hone)/i ) {
			$options{type} = 'text';
			$options{pattern} = '[\+\-]?[.0-9eE]*' if ! $options{pattern};
		#} elsif ( $ENV{HTTP_USER_AGENT} =~ /Firefox/ ) {
			#$options{type} = 'text';
			#$options{pattern} = '^[\+\-]?[.0-9eE]*' if ! $options{pattern};
			#delete $options{step};
		} else {
			$options{type} = 'number';
		} # end if
		$options{oninput} = 'floatize(this);'.$options{oninput};
    } elsif ( $options{type} eq 'positivefloat' ) {
#$log->debug("USer agent: $ENV{HTTP_USER_AGENT}");
        $options{step} = 'any' if ! exists $options{step};
        if ( $ENV{HTTP_USER_AGENT} =~ /ip(ad|od|hone)/i ) {
            $options{type} = 'text';
            $options{pattern} = '[.0-9eE]*' if ! $options{pattern};
        } elsif ( $ENV{HTTP_USER_AGENT} =~ /Firefox/ ) {
            $options{type} = 'text';
            $options{pattern} = '[.0-9eE]*' if ! $options{pattern};
            delete $options{step};
        } else {
            $options{type} = 'number';
        } # end if
        $options{oninput} = 'positive_floatize(this);'.$options{oninput};
	} elsif ( $options{type} eq 'float_calculator' ) {
		if ( $ENV{HTTP_USER_AGENT} =~ /ip(ad|od|hone)/i ) {
			$options{type} = 'text';
			$options{pattern} = '[0-9\*\+=\/\.\-]*' if ! $options{pattern};
    } elsif ( $ENV{HTTP_USER_AGENT} =~ /Firefox/ ) {
      $options{type} = 'text';
      $options{pattern} = '[0-9\*\+=\/\.\-]*' if ! $options{pattern};
      delete $options{step};
    } else {
			$options{type} = 'text';
		} # end if
		$options{step} = 'any' if ! exists $options{step};
		$options{oninput} = 'floatize_calculator(this);'.$options{oninput};
	} elsif ( $options{type} eq 'ip' ) {
		$options{pattern} = '[0-9\/\.:a-fA-F]*' if ! $options{pattern};
		$options{type} = 'text';
		$options{step} = 'any' if ! exists $options{step};
		$options{oninput} = q`this.value=this.value.replace(/[^\.\d%\/\*a-fA-F:]/g,'');`.$options{oninput};
	} elsif ( $options{type} eq 'mac' ) {
		$options{pattern} = '[0-9\-:a-fA-F]*' if ! $options{pattern};
		$options{type} = 'text';
		$options{step} = 'any' if ! exists $options{step};
		$options{oninput} = q`this.value=this.value.replace(/[^\-\d%\/\*a-fA-F:]/g,'');`.$options{oninput};
	} # end if
	$html .= ' value="'.html_escape($options{value}).'"' if $options{value} ne '';

	if ( $options{with_clear} ) {
		$options{class} = $options{class} ? $options{class} . ' input-clear' : 'input-clear';
	}
	foreach (@input_options) {
		$html .= qq` $_="$options{$_}"` if exists $options{$_};
	} # end foreach
	$html .= ' required' if $options{required};
	$html .= ' readonly="readonly"' if $options{readonly};
	$html .= '/>';
	if ( $options{with_clear} ) {
		$html .= qq`<span class="input-clear" title="clear input" onclick="this.previousSibling.value='';this.previousSibling.focus();">x</span>`;
		#$html .= qq`<span class="input-clear" onclick="this.parentNode.value='';this.parentNode.focus();\$j('[name=$options{name}]').val('').focus();">x</span>`;
	}
	return $html;
} # end sub input

my %make_dropdown_options = map { $_=>$_} ('prepend','append','encode','length');

sub select( $$$ ) {
	my ( $data, $selected, $options ) = @_;
	my $html = '<select' . join(' ', '', map { exists $make_dropdown_options{$_} ? () : $_.'="'.$$options{$_}.'"' } keys %{$options} ) . '>';
	$html .= make_drop_down( $data, $selected, $options );
	$html .= '</select>';
} # end sub select($$$)

sub translate($) {
	if ( ! defined $Lexicon ) {
		%$Lexicon = sql::execute( undef, undef, 'SELECT word, translation FROM Lexicon '  );
	} # end if
	return $$Lexicon{$_[0]} if $$Lexicon{$_[0]};
	return $_[0];
} # end sub translate

sub reset_session($) {
	foreach my $k ( keys %openprint::session ) {
		if ( $k =~ /^$_[0]/ ) {
			delete $openprint::session{$k};
		} #end if
	} # end foreach
	%param = ();
	#$variable{ExternalRedirect} = $_[0];
} # end sub reset_session


# If there is any problem, return the original path, so that the original file can be sent.
sub hash_link {
	my ( $path ) = @_;

	my $src;
  if ( -e $path ) {
    $src = $path;
	} elsif ( -e $config{SkinPath}.$path ) {
		$src = $config{SkinPath}.$path;
	} elsif ( -e $ENV{DOCUMENT_ROOT}.$path ) {
		$src = $ENV{DOCUMENT_ROOT}.$path;
	} else {
		return $path;
	} # end if

	require JSON;
	require Digest::MD5;

	$config{cache_dir} = $config{SkinPath}.'/cache' if ! $config{cache_dir};

	my $script;
	if ( ( ! $hash_cache{$config{SkinPath}} ) and -f $config{cache_dir}.'/config.json' ) {
		$_ = File::Slurp::read_file($config{cache_dir}.'/config.json');
		if ( $_ ) {
			$hash_cache{$config{SkinPath}} = JSON::from_json( $_ );
			$hash_cache{$config{SkinPath}} = {} if ! $hash_cache{$config{SkinPath}};
		} else {
			$log->error("No content of $config{cache_dir}/config.json");
			$hash_cache{$config{SkinPath}} = {};
		} # end if
	} # end if

	my @stat = stat $src;
  my $timestamp = $stat[9];

	if ( !($script = $hash_cache{$config{SkinPath}}{$path})
			|| ! -f $$script{cache_file}
			|| ($timestamp > $script->{timestamp})
	   ) {

		my ($base, $dir, $ext) = fileparse $src, qr/\.[^.]+/;
		$ext =~ s/^\.//;
		my $blob = File::Slurp::read_file($src);

		if ( ! $config{debug} ) {
			if ( $ext eq 'js' ) {
				require JavaScript::Minifier::XS;
				eval { $blob = &JavaScript::Minifier::XS::minify( $blob ); };
				$log->error( "Eval error of (minify), Reason: " . $@ ) if $@;

			} elsif ( $ext eq 'css' ) {
				require CSS::Minifier;
				$blob = &CSS::Minifier::minify( input=>$blob );
			} # end if
		} # end if

		my $hash = Digest::MD5::md5_hex($blob);
		$hash_cache{$config{SkinPath}}{$path} = $script = {
			src			=>	$src,
			name		=> "$base-$hash.$ext",
			path		=> $path,
			cache_file	=> "$config{cache_dir}/$base-$hash.$ext",
			hash		=> $hash,
			timestamp	=> $timestamp,
		};
		if ( ! -f $$script{cache_file} ) {
			mkdir $config{cache_dir};
			if ( ! File::Slurp::write_file($script->{cache_file},       { atomic => 1, err_mode=>'carp' }, \$blob) ) {
				$log->error( "couldn't cache $script->{cache_file}" );
				return $path;
			} # end if
			`gzip -c -9 "$$script{cache_file}" > "$$script{cache_file}.gz"`;
			File::Slurp::write_file($config{cache_dir}.'/config.json', { atomic => 1, err_mode=>'carp' }, JSON::to_json($hash_cache{$config{SkinPath}}, {pretty => 1})) or warn "Couldn't save cache control file";
		} # end if
	#} else {

$log->debug("HASH CACHED $path ($$script{cache_file} ($timestamp) ($$script{timestamp}) @stat");
	} # end if

	# cache_path is the url part
	return ($config{cache_path}?$config{cache_path}:'/cache').'/'.$script->{name};
} # end sub hash_link

sub format_date {
	return $_[0] ? Date::Format::time2str( $_[1] ? $_[1] : $config{DateFormat}, Date::Parse::str2time( $_[0] ) ) : '';
} # end sub format_date

sub format_datetime {
	return $_[0] ? Date::Format::time2str( $config{DateTimeFormat}, Date::Parse::str2time( $_[0] ) ) : $_[1];
} # end sub format_datetime

sub format_time {
	return $_[0] ? Date::Format::time2str('%H:%M', Date::Parse::str2time($_[0])) : '';
} # end sub format_time

sub format_csv_datetime {
	return $_[0] ? Date::Format::time2str( '%Y-%m-%d %H:%M:%S', Date::Parse::str2time( $_[0] ) ) : $_[1];
} # end sub format_datetime

sub format_csv_date {
	return $_[0] ? Date::Format::time2str( '%Y-%m-%d', Date::Parse::str2time( $_[0] ) ) : '';
} # end sub format_datetime

sub link {
	return '<link rel="stylesheet" type="text/css" href="'.hash_link($_[0]).'"/>';
}

sub include_logs {
	my $Object = $_[0];
	$variable{Object} = $Object;
	setup_date_select( $variable{uri}, 'log_created_on_start', -31 );
	setup_date_select( $variable{uri}, 'log_created_on_end', '' );
	$session{$variable{uri}.'?log_limit'} = 50 if ! exists $session{$variable{uri}.'?log_limit'};
	return include('/includes/_logs_container.html');
}
sub include_logs_view {
	my $Object = $_[0];
	$variable{Object} = $Object;
	setup_date_select( $variable{uri}, 'log_created_on_start', -31 );
	setup_date_select( $variable{uri}, 'log_created_on_end', '' );
	$session{$variable{uri}.'?log_limit'} = 50 if ! exists $session{$variable{uri}.'?log_limit'};
	return include('/includes/_logs_contents_view.html');
}

sub do_css_links {
  my @html;
  my $css = shift;
  $log->debug("DO css for $css");

  $css =~ s/^\///;
  $css =~ s/^openprint\///;
  $css =~ s/\..+$//;
  my @parts = split '/', $css;
  $log->debug("Parts: @parts") if Debug;

  while ( @parts ) {
    $css = join('_', @parts ) . '.css';
    #$log->debug("$css");
    if ( -e $config{SkinPath}.'/css/'.$css ) {
      #$log->debug("exist at " . $config{SkinPath}.'/css/'.$css);
      push @html, '<link type="text/css" rel="stylesheet" href="'.hash_link($config{SkinPath}.'/css/'.$css).'"/>';
    } elsif ( Debug ) {
      $log->debug('Does not exist at ' . $config{SkinPath}.'/css/'.$css);
    } # end if
    if ( -e $ENV{DOCUMENT_ROOT}.'/css/'.$css ) {
      #$log->debug("xist at " . $ENV{DOCUMENT_ROOT}.'/css/'.$css);
      push @html, '<link type="text/css" rel="stylesheet" href="'.hash_link($ENV{DOCUMENT_ROOT}.'/css/'.$css).'"/>';
    } elsif ( Debug ) {
      $log->debug('Does not exist at ' . $ENV{DOCUMENT_ROOT}.'/css/'.$css);
    }
    pop @parts;
  } # end while
  return join("\n", reverse @html);
}

sub navmenu {
  my $menu = shift;
  my $current_uri = shift;

  my $html;
  my $on = 0;

  my @categories;
  if ( ref $menu eq 'ARRAY' ) {
    my %m = @{$menu};
    while (@{$menu}) {
      push @categories, shift @{$menu};
      shift @{$menu};
    }
    $menu = \%m;
  } elsif (exists $$menu{options}) {
    @categories = sort { $a cmp $b } $$menu{options};
  } else {
    @categories = sort { $a cmp $b } keys %{$menu};
  }

  foreach my $category ( @categories ) {
    if ( ref $$menu{$category} ) {
      my @keys;
      my %urls;
      my $category_on = 0;

      if ( ref $$menu{$category} eq 'ARRAY' ) {
        %urls = @{$$menu{$category}};
        # Maintain ordering
        while(@{$$menu{$category}}) {
          push @keys, shift @{$$menu{$category}};
          shift @{$$menu{$category}};
        }
      } elsif ( ref $$menu{$category} eq 'HASH' ) {
        %urls = %{$$menu{$category}};
        @keys =  sort { $urls{$a} cmp $urls{$b} } keys %urls;
      }
      my $submenu_html;
      foreach my $url (@keys) {
        if (ref $urls{$url}) {
          my ($sub_html, $new_on) = navmenu({$url=>$urls{$url}}, $current_uri);
          $submenu_html .= $sub_html;
          $category_on = 1 if $new_on;
        } else {
          my $text = $urls{$url};
          if ( $text ) {
            my $Page_Setting = openprint::Page_Setting::get( $url );
            if ( $Page_Setting->can_view() ) {
              $submenu_html .= sprintf('<li%s><a href="%s">%s</a></li>', ($current_uri eq $url ? ' class="on"':''), $url, $urls{$url} );
              $submenu_html .= "\n";
            } # end if
          }
          $category_on = 1 if $current_uri eq $url;
#$log->error("Setting on to $on because $current_uri eq $url");
        } # end if submenu
      } # end foreach url

      if ( $submenu_html ) {
        $html .= join( $submenu_html,
          sprintf(q`
            <li id="%1$sMenu" class="%2$s"><a href="#" onclick="toggleMenu($('%1$sMenu'), 'off', 'on');return false;">%1$s</a>
            <ul>`, $category, ( $category_on ? 'on' : 'off' ) ),'</ul>
          </li>
          ' );
      }
      $on = $category_on;
    } else {
      $html .= sprintf( q`
        <li id="%1$sMenu" class="menu-item %2$s"><a href="%2$s">%1$s</a></li>
        `, $category, $$menu{$category} );
    }
  } # end foreach category
  if (wantarray) {
    return ($html, $on);
  }
  return $html;
}

sub bootstrap_navmenu {
	my $menu = shift;
	my $current_uri = shift;

	my $html;
	my $on = 0;

  my @categories;
  if ( ref $menu eq 'ARRAY' ) {
    @categories = map { $_ % 2 ? () : $$menu[$_] } 0 .. (scalar @{$menu}-1);
    my %m = @{$menu};
    $menu = \%m;
  } else {
    @categories = sort keys %{$menu};
  }
	foreach my $category ( @categories ) {
    my $category_id = $category;
    $category_id =~ s/\s+//g;

		if ( ref $$menu{$category} eq 'HASH' ) {
my %urls;
      if (exists $$menu{options}) {
        %urls = %{$$menu{options}};
} else {
			 %urls = %{$$menu{$category}};
}
			my $submenu_html = '';
			foreach my $url ( sort { $urls{$a} cmp $urls{$b} } keys %urls ) {
				my $text = $urls{$url};
				if ( $text ) {
					my $Page_Setting = openprint::Page_Setting::get( $url );
					if ( $Page_Setting->can_view() ) {
						$submenu_html .= sprintf('<li class="dropdown-item"><a href="%s">%s</a></li>', $url, $text )."\n";
          } else {
            $log->debug("Not permitted to view $url");
					} # end if
				}
				$on = 1 if $current_uri eq $url;
			} # end foreach url

			if ( $submenu_html ) {
				$html .= join( $submenu_html,
						sprintf(q`
							<li class="nav-item dropdown %3$s">
							<a href="#" id="%1$sMenu" class="nav-link dropdown-toggle" role="button" data-bs-toggle="dropdown" aria-expanded="false">%2$s</a>
							<ul id="%1$sSubMenu" class="dropdown-menu" aria-labelledby="%1$sMenu">`,
              $category_id,
							$category,
							( $on ? ('active','true' ) : ( '', 'collapse' ) ),
							),'</ul></li>' );
			}
    } elsif ( ref $$menu{$category} eq 'ARRAY' ) {
      my $submenu_html = '';
      my $on = 0;
      while ( my ($url, $text) = splice(@{$$menu{$category}}, 0, 2) ) {
        if ($text) {
          my $Page_Setting = openprint::Page_Setting::get($url);
          if ($Page_Setting->can_view()) {
            $submenu_html .= sprintf('<li><a class="dropdown-item" href="%1$s">%2$s</a></li>', $url, $text )."\n";
          } else {
            $log->debug("Not permitted to view $url");
          } # end if
          #} else {
          #$log->error("No text for $url");
        }
        $on = 1 if $current_uri eq $url;
      } # end foreach url

      if ($submenu_html) {
        $html .= join($submenu_html,
            sprintf(q`
              <li class="nav-item dropdown %3$s">
              <a href="#" id="%1$sMenu" class="nav-link dropdown-toggle" %5$s role="button" data-bs-toggle="dropdown" aria-expanded="false">%2$s</a>
              <ul id="%1$sSubMenu" class="dropdown-menu list-unstyled" aria-labelledby="%1$sMenu">`,
              $category_id,
              $category,
              ( $on ? ('active','true','aria-current="page"' ) : ( '', 'false', 'collapse', '' ) ),
              ),'</ul></li>' );
      }
		} else {
      my $url = $$menu{$category};
      my $Page_Setting = openprint::Page_Setting::get( $url );
      if ($Page_Setting->can_view()) {
        $html .= sprintf( q`<li id="%1$sMenu" class="nav-item %3$s"><a href="%3$s">%2$s</a></li>`, $category_id, $category, $url);
      } else {
        $log->debug("Not permitted to view $url");
      }
    }
	} # end foreach category
  #$log->error($html);
	return $html;
}

1;
__END__
