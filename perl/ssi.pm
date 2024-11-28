# SSI
#
# Hand rolled recursive regular expression parsed SSI/templating system. Badly
# in need of being replaced with something else.
package ssi;
use strict;
use warnings;
no warnings qw(uninitialized);

BEGIN {
    use base qw( Exporter );

    our @EXPORT_OK = qw(
        variable_substitution insert_html        htmlize
        make_drop_down        material_drop_down fill_drop_down
        make_select           fill_select        return_states_and_provinces
        return_states         return_countries   getyears
        getmonths             getdays            getemployee_numbers
        getannual_sales       get_range_text     get_start_end_dates
        get_dates			  get_file_path
		$gdb
    );

    our %EXPORT_TAGS = ( all => \@EXPORT_OK );
}
our $gdb;

#Used for resource hashed links
my $hash_cache;
use vars qw( $r %variable %session %param %config $log $dbh );
*session = \%openprint::session;
*param = \%openprint::param;
*log = \$openprint::log;
*variable = \%openprint::variable;
*config = \%openprint::config;
*r = \$openprint::r;
$dbh = session::dbh;

# If set to 1, SSI will die on keys that don't exists, otherwise we silently
# ignore them.
our $INVALID_KEY = 0;

use constant MAX_DEPTH => 30; # Maximum include depth.

use Carp;
use Date::Calc qw(Days_in_Month);
use Date::Parse;
use Date::Format;
use sql qw(sql_statement);
use PQS::Constants;

require countries;
require states;
require provinces;

# MODIFIER TABLE
#
# A modifier is a unary function that takes a scalar and returns a string.
# They're used in SSI to modify the value before it's replaced in the output.
use Apache2::SubRequest ();
use HTML::Entities;
use Data::Dumper qw( Dumper            );
use POSIX        (); # Don't import (memory issues)
use Scalar::Util qw( looks_like_number );
use List::Util   qw( min               );
require File::Slurp;
require File::Basename;

use constant NUMBER => 
    qw(zero one two three four five six seven eight nine ten);

our %MODIFIERS = (
    # Truth
    'not' => sub { !$_[0] },

    # Standard POSIX operations.
    'int'       => sub { int(             $_[0] ) },
    floor       => sub { POSIX::floor(    $_[0] ) },
    ceil        => sub { POSIX::ceil(     $_[0] ) },
    float       => sub { sprintf( '%.2f', $_[0] ) },

    # Wrappers around some standard utility functions.
    'ucfirst'   => sub { ucfirst(         $_[0] ) },
    'uc'        => sub { uc(              $_[0] ) },
    'lc'        => sub { lc(              $_[0] ) },
    escape_html => sub { encode_entities(     $_[0] ) },
    Dumper      => sub { Dumper(          $_[0] ) },
    newline     => sub { $_[0] =~ s/\r/<br>/g;    return $_[0]; },

    # Formats a number as n.nn using sprintf's IEEE rounding. If the input
    # doesn't look like a number it returns an empty string. TODO: Get
    # currency symbol from user ID (will be a yucky global lookup).
    money => sub {
        my ($num) = @_;

        return $num unless looks_like_number($num);
    	return ''   unless $num;

        return sprintf '$ %.2f', $num;
    },

    # Allows constructs like <?if multiple:foos ?> to add the plural of a word.
    multiple => sub { 
        my $n = shift;
        
        return 0 unless defined $n; 
        
        return (ref $n eq 'ARRAY' ? scalar @$n : $n+0) > 1
    },
    
    # Convert numbers under ten to their english word
    number   => sub {
        my $num = shift;
        return '' unless defined $num && looks_like_number($num);

        return $num if $num > 10;

        return (NUMBER)[$num];
    },

    # Check to see if the given value is empty.
    empty => sub { 
        my $ref = ref $_[0];
        return $ref eq 'ARRAY' ? ! scalar      @{ $_[0] }
             : $ref eq 'HASH'  ? ! scalar keys %{ $_[0] }
             : !$ref           ? ! defined $_[0] || $_[0] eq ''
             :                 undef
     },

     # Give the "size" of arrays, hashes (number of hash keys), and strings.
     size => sub {
        my $ref = ref $_[0];
        return $ref eq 'ARRAY' ? scalar      @{ $_[0] }
             : $ref eq 'HASH'  ? scalar keys %{ $_[0] }
             : !$ref           ? length $ref
             :                 undef
     },

	 rev => sub {
        my $id = shift;

		my $rev = $gdb->selectrow_array(q{
			SELECT rev FROM tbl_orders WHERE lngorderid = ?
		}, undef, $id); 


		return $id ? $id . "-$rev" : '';

	 },
);

# Core section for tag directives and variable replacement. Includes are
# handled elsewhere.
sub do_new_substitution {
    my ( $r, $log, $dbh, $command, $text, $variable ) = @_;

    # WHILE control structure.
    if ( $command =~ /while\s*\(\s*(.*)\s*\)/ ) {
        my $dataname = $1;
        if ( $text =~ /(.*?)<\?\s*endwhile\s*\(\s*\Q$dataname\E\s*\)\s*\?>(.*)/si ) {
            my $middle = $1;
            my $end = $2;
            my $replacement_text = '';
            $dataname = variable_substitution( $r, $log, $dbh, $dataname, $variable );
            while ( 1 ) {
                $_ = eval $dataname;
                $log->error( "Eval error of ($dataname), Reason: " . $@ ) if $@;
              last if ! $_;
                $replacement_text .= variable_substitution( $r, $log, $dbh, $middle, $variable );
            }
            return $replacement_text . variable_substitution( $r, $log, $dbh, $end, $variable );
        } else {
            $log->debug("Unable to find terminating $command");
            return variable_substitution( $r, $log, $dbh, $text, $variable );
        }
    }

    # IF control structure.
    elsif ( $command =~ /^\s*if\s*(.*)\s*/ ) {
        my $dataname = $1;
        #$log->debug("Found if $dataname");
        unless ($text =~ /(.*?)<\?\s*endif\s*\Q$dataname\E\s*\?>(.*)/si) 
        {
            $log->debug("Unable to find terminating $command for $dataname in $text");
            return variable_substitution( $r, $log, $dbh, $text, $variable );
        }

        my $middle           = $1;
        my $end              = $2;
        my $replacement_text = '';
        my $elsetext         = '';

        if ( $middle =~ /(.*?)<\?\s*else\s*\Q$dataname\E\s*\?>(.*)/si ) {
            $middle = $1;
            $elsetext = $2;
        }

        my $bool;
        if ($dataname =~ /^(?:\w+:)*(?:[A-Za-z_0-9]+.)*[A-Za-z_0-9]+$/) {
          #$log->debug("Evalling $dataname");
            $bool = eval_variable($log, $variable, $dataname);
        }
        else {
            $bool = eval $dataname;
            $log->error( "Eval error of ($dataname), Reason:" . $@ ) if $@;
        }

        if ($bool) {
            $replacement_text 
                .= variable_substitution($r, $log, $dbh, $middle, $variable);
        } 
        elsif ($elsetext ne '') {
            $replacement_text 
                .= variable_substitution($r, $log, $dbh, $elsetext, $variable);
        }
        
        return $replacement_text . variable_substitution( $r, $log, $dbh, $end, $variable );
    }


    # LOOP control stucture
    #
    #  Usage: <? loop foo ?>
    #
    #  Where foo is a key to $variable that contains an array of hashes to be
    #  looped over. It may be a multipart key in the form 'foo.bar.baz' or a
    #  simple one. The hash names clobber any identical <?var?> names within
    #  the loop but they are restored once outside of it.
    #
    #  Loops keep an internal row counter that can be accessed as <?_row?>.
    #
    #  As a side note, because variables are clobbered internal loops can be
    #  referenced without their full prefix. ie. in "loop foo.bar ... loop
    #  baz" the loop baz actually refers to foo.bar.[ annon array ].baz.
    #
    elsif ( $command =~ /loop\s+\(?\s*(.*)\s*\)?/i ) {

        my $loop = $1;

        # Allow the loop name to be in the foo.bar.baz form.
        my $array = ($loop =~ /\./) ? dereference($log, $variable, $loop)
                                    : $variable->{$loop};

        # Convert a hash into an array of hashes.
        $array = [ map { { key => $_, value => $array->{$_} } } keys %$array ]
            if ref $array eq 'HASH';

        die "$loop is not an array reference: $!\n"
            unless ref $array eq 'ARRAY' or not defined $array;

        # Following the other structures the loop gets terminated by an
        # 'endloop' directive.
        $text =~ /(.*?)<\?\s*endloop\s+\(?\s*\Q$loop\E\s*\)?\s*\?>(.*)?/si
            or die "Cannot find terminating endloop ($loop).\n";

        my ($inside_tag, $after_tag, $replace) = ($1, $2, '');

        # Initialise a row counter and 'even' counter. Row counter is
        # obvious, even counter is row % 2, useful for things like greenbar
        # effects.
        local $variable->{_row}   = 0;
        local $variable->{_even}  = 0;
        local $variable->{_first} = 0;
        local $variable->{_last}  = 0;

        # For memory and speed reasons we may need to move the local outside
        # the loop and use the first element of the array of hashes to define
        # the keys to localise. Then make sure all hashes conform to that set.
        my $i = 0;
        for my $hash ( @$array ) {
            # Localise the changes so they're available to all called functions
            # but we restore the originals outside the loop block.
            local @$variable{ keys %$hash } = values %$hash;

            $variable->{_row}++;
            $variable->{_even} = $variable->{_row} % 2;

            $variable->{_first} = ($i == 0);
            $variable->{_last}  = (@$array == $i+1);
            $variable->{"_last_$loop"}  = (@$array == $i+1);
            $i++;

            $replace .= variable_substitution( $r, $log, $dbh,
                                               $inside_tag, $variable );
        }

        return $replace . variable_substitution( $r, $log, $dbh,
                                                 $after_tag, $variable );
    }

    # POP control structure.
    #
    # Usage:
    #         <? pop (foo, bar, baz) = qux ?>
    #
    # Where foo, bar, and baz are the key names to assign into the varaiable
    # hash and qux is a key to said hash with a value of a array reference.
    #
    # Unlike the name suggests, the function actually shifts the elements off
    # the top of the array instead of popping it off the bottom.
    #
    # Fun huh? -- Raymond
    #
    elsif ( $command =~ /pop\s*\((.*)\)\s*=\s*([\%\w]*)/i ) {
        my $variables = $1;
        my $dataname = variable_substitution( $r, $log, $dbh, $2, $variable );
        my @var_names = split( ',', $variables );
        foreach my $name ( @var_names ) {
            $name =~ s/^\s*(\w+)\s*$/$1/;
            $$variable{$name} = shift @{$$variable{$dataname}};
        }
        return variable_substitution( $r, $log, $dbh, $text, $variable );
    }

    # EVAL control structure.
    elsif ( $command =~ /eval\s*\(\s*(.*)\s*\)/ms ) {
        $_ = eval $1;
        $log->error( "Eval error of ($1), Reason: " . $@ ) if $@;
        return variable_substitution( $r, $log, $dbh, $text, $variable );
    }

    # Echo control structure.
    elsif ( $command =~ /echo\s*\(\s*(.*)\s*\)/ms ) {
      #$log->debug("Echo $1");
        my $return = eval $1;
        $log->error( "Eval error of ($1), Reason: " . $@ ) if $@;
        #$log->debug("Return : $return");
        return $return.variable_substitution( $r, $log, $dbh, $text, $variable );
    }
    elsif ( $command =~ /^include\s*\(\s*'?([^'\)]*)'?\s*\)/ms ) {
      #$log->debug("Include $1");
        my $return = include( $1, $variable );
        return $return.variable_substitution( $r, $log, $dbh, $text, $variable );
    }
    # Dump all of $variable into the text stream.
    elsif ( $command =~ /dumper\s*\(\)/ ) {
        return Dumper($variable) 
             . variable_substitution( $r, $log, $dbh, $text, $variable );
    }
    elsif ( $command =~ /^hash_link\s*\(\s*'?([^\s']+)'?\s*\)/ms ) {
        return hash_link($1).variable_substitution( $r, $log, $dbh, $text, $variable );
      }
    # Straight variable substitution
    else {
      #$log->debug($command);
        my $replacement = eval_variable($log, $variable, $command);

        return $replacement
             . variable_substitution( $r, $log, $dbh, $text, $variable );
    }
}

sub eval_variable {
    my ($log, $variable, $command) = @_;

    # A variable name may be prepended by one or more modifiers. A
    # modifier is a unary transform postfixed with a colon. For example,
    # 'price:number'.
    my @modifiers = split /:/, $command;

    my $name = pop @modifiers; # Last bit is our variable name.

    # If the variable has a '.' in it we treat it as a multipart key.
    # Otherwise it's assumed to be a straight access to $variable. The
    # check to make sure it's not the last character is for the legacy way
    # 'checked'ing salutation radio buttons.
    my $replacement;

    if ($name =~ /\./ and not $name =~ /\.$/) {
        $replacement = dereference($log, $variable, $name); }
    else {
        die "Could not find key '$name'\n"
            if $INVALID_KEY and not exists $variable->{$name};
        $replacement = $variable->{$name};
    }

    # Modifiers are right associative (run in reverse order) and can be
    # chained. eg. 'currency:price:number' might format the number as a
    # price then prepend a currency symbol to it.
    MODIFIER:
    for my $mod (reverse @modifiers) {
        if (not exists $MODIFIERS{ $mod }) {
            carp "SSI modifier $mod does not exist.";
            next MODIFIER;
        }

        # The replacement text is filtered through the modifier.
        $replacement = &{ $MODIFIERS{ $mod } }($replacement);
    }

    return $replacement;
}


# Internal sub used for dereferencing multipart key variable calls. Eg. Turns
# <?  foo.bar.baz ?> into $variable->{foo}{bar}{baz}.
sub dereference {
    my $log        = shift;
    my $variable   = shift;  # Special $variable hash ref
    my $keystring  = shift;  # Stringified key names eg. 'foo.bar.baz'

    # Our syntax uses '.' to dereference instead of Perl's '->'.
    my @keychain = split /\./, $keystring;

    # The first key in the chain is always a hash key as everything uses the
    # special $variable hash ref.
    my $key = shift @keychain;
    my $val = $variable->{$key};

    # For all other keys in the chain we determine if it's a hash or array the
    # key refers to,
    foreach $key (@keychain) {
        my $type = ref $val;

        # We don't currently check that array and hash keys are valid for their
        # types. At least simple checks such as making sure array keys are ints
        # should be done.
        if    ($type eq 'HASH')  { $val = $val->{$key} }
        elsif ($type eq 'ARRAY') { $val = $val->[$key] }
        else                     {
            die "Invalid reference ($val): $!" if $INVALID_KEY
        }
    }

    return $val;
}


#i'm adding more and more recursion in an attempt to make this faster.
# this big bottleneck is all the regexp searches through the text.
# the text is huge, so the more we break it down, the faster these get.
# -- Issac?
#
# This DEFINITELY needs to be gotten rid of. Rewriting yet another variable
# substitution templating system is a waste of time. There are tons of other
# systems that use much faster token parsing and compile the templates down
# to pcode (or even C). Choose one. -- Raymond
#
# There's that, and they actually, y'know, *cough*, work.
sub variable_substitution {
    my ( $r, $log, $dbh, $text, $variable, $depth ) = @_;

    my $sslocation = $r->dir_config('site_specific');

    if ( $text =~ /(.*?)<\?\s*(.*?)\s*\?>(.*)/s ) {
        my $command = $2;
        my $after = $3;
        my $before = variable_substitution( $r, $log, $dbh, $1, $variable );
        $text = $before . do_new_substitution( $r, $log, $dbh, $command, $after, $variable );
    }

    $depth = defined $depth ? $depth + 1 : 1;

    die "Too many levels of includes ($depth). Possible recursive include or include loop."
        if $depth >= MAX_DEPTH;

    while ( my ($filename) = ( $text =~ /<!--#include\s+virtual="(.*?)"\s*-->/i )) {

        #re-write path for site specific files
        $filename = $sslocation . '/' . $filename if $filename =~/^\/?site_specific/;

        # Due to the dynamic generation of CSS on browser request, we need to call
        # the generation routine before trying to include any CSS in emails.
        css_subsitution($r, $filename)
            or $log->warn("Could not generate the included css")
            if $filename =~ /\.css$/ && $filename =~/^\/?site_specific/;

        # Allow variables within the filename being included.
        my $file = variable_substitution(
            $r, $log, $dbh, $filename, $variable, $depth
        );

        # Run the variable substitution over the included file and insert it's
        # text into the current location before continuing.
        my $insert_text = variable_substitution(
            $r, $log, $dbh, insert_html($r, $file), $variable, $depth
        );

		$insert_text = "<!-- START INCLUDE $file --> \n " . 
		                $insert_text .
		               "\n <!-- END   INCLUDE $file --> \n " 
		unless $file =~ /title/ || ! DEBUG || $file =~ /css/;

        $text =~ s/<!--#include\s+virtual="(.*?)"\s*-->/$insert_text/i;
    }

    $depth--;

    return $text;
}

sub css_subsitution {
    # Primes the cache so the file exits when it is included into the page
	my ($r, $file_name) = @_;
	$r->subprocess_env(internal  => 1);
	my $subr = $r->lookup_uri($file_name);
	return $subr->run;
}

# Prints out the contents of a page, used to include one page in another.
sub insert_html {
    my $r    = shift;
    my $page = shift;
    my $data = '';

    # Slurp in the file (there should be locking here).
    my $filename = get_file_path($r, $page);
    open (PAGE, "$filename") or return "Could not open $filename";
    $data = do { local $/ = undef; <PAGE> };
    close PAGE;

    return $data;
}

sub get_file_path {
	my ($r, $page ) = @_;

    my $path = $r->document_root; # Default path to look for includes.

    # If a file is already declared as customer_specific
    if ($page =~ /^.?customer_specific(.*)$/) {
      my $cs = $r->dir_config('custom_skin');
      return "$cs/$1";
    }

    # If a file is already declared as site_specific..
    if ($page =~ /^.?site_specific(.*)$/) {
        # If the site_specific variable is set in Apache, we remove the
        # 'site_specific' and look for the file in the provided dir.
		my $cs = $r->dir_config('custom_skin');

		if ( $cs && -e "$cs/$1" ) {
            $path = $cs;
            $page = $1;
		} elsif ( $r->dir_config('site_specific') ) {
            $path = $r->dir_config('site_specific');
            $page = $1;
        }
    }
    # If it's not declared as site_specific by default it is still permissable
    # to be there. If it is there it's treated as an 'override' to the
    # template version in the normal dir.
    else {
        my $cs = $r->dir_config('custom_skin');
	    my $ss = $r->dir_config('site_specific') || "$path/site_specific";

        $path =   $cs && -e "$cs/$page" ? $cs 
			    : $ss && -e "$ss/$page" ? $ss
                : $path;
    }
	return "$path/$page";


}

# This shouldn't even be here.  HTML::Entities, etc exist for a reason.
sub htmlize {
    map { s/"/&quot;/g; $_ } @_;
    return wantarray ? @_ : $_[0];
}

# This is left for comedic value:
#sub htmlize {
#    if ( @_ == 1 ) {
#        $_ = shift;
#        $_ =~ s/"/&quot;/g;
#        return $_;
#    }
#    for( $_ = 0; $_ < @_; $_ += 1 ) {
#        $_[$_] =~ s/"/&quot;/g;
#    }
#    return @_;
#}


sub select_options {
	my $table 	= shift;
	my $col1 	= shift;
	my $col2 	= shift;
	
	my $dbh = session::dbh;

	my $sql = qq{SELECT $col1, $col2 FROM $table order by $col2};
	my $data = $dbh->selectall_arrayref($sql);


	return ssi::make_drop_down($data);
	
}

# Populate the <options>s of an HTML select element. Takes a flat array of
# what should be pairs, a SINGLE value to select, and an option maximum label
# length.
sub make_drop_down {
    my ( $val, $checkval, $length ) = @_;
    my ( $options, $selected ) = ('', '');
    my @data;
	


	my $value;
	my $label;

	my $x = ref $val;
	print STDERR "START MAKE: $x \n";
    # Return an empty string if no data was passed.
    if    (ref $val eq 'HASH')                           { @data = %$val }
    elsif (ref $val eq 'ARRAY') 						 { @data = @$val }
    else                                                 { return;       }

    while (@data) {
		if ( ref $data[0] eq 'ARRAY' ) {
			my $row = shift @data;
			$value = shift @$row;
			$label = shift @$row;
		} else { 
			$value = shift @data;
			$label = shift @data;
		}

        # Should the current option be selected?
        $selected = defined $checkval && $checkval eq $value 
            ? 'selected="selected"' : '';

        # Escape html entities where needed and trim label length.
        $value = encode_entities( $value );
        $label = encode_entities( $length ? substr($label, 0, $length) : $label );

        # Output the option.
        $options .= qq|<option value="$value" $selected>$label</option>\n|;
    }
    # Return an HTML text block of options.
    return $options;
}

# Generate an HTML option set (as a string) of materials in the given type.
# Optionally selects one of the materials if it's id matches one in the list.
sub material_drop_down {
    my $log      = shift;
    my $dbh      = shift;
    my $type     = shift; # The material type.
    my $selected = shift; # The selected element.
    my @types;            # Flattened list of material id/name pairs.

    # Remove spaces and lowercase the supplied string for lookup.
    $type =~ tr/ //d;
    $type = lc($type);

    # Return a list of id, name pairs of materials in the type.  Make sure to
    # use the functional index so we don't have problems with capitalisation
    # or spacing.
    my $sth = $dbh->prepare(q{
        SELECT m.strid, m.strname
        FROM tbl_materials m, material_type t
        WHERE m.lngtype = t.id
          AND lower(replace(t.name, ' ', '')) = ?
        ORDER BY name
    });
    $sth->execute($type);

    # Flatten the list of pairs into a list.
    push @types, @$_ while local $_ = $sth->fetch;

    # Return the generated string of HTML option elements.
    return make_drop_down( \@types, $selected );
}

sub fill_drop_down {
    my ( $log, $dbh, $search, $checkval, $length ) = @_;
    my ( $temp, @search_data, $n, $checked);

    @search_data = sql_statement( $log, $dbh, $search );

    return make_drop_down( \@search_data, $checkval, $length );
}

sub make_select {
    my ( $options, $checkarray, $length ) = @_;

    my $temp = '';

    for ( my $n = 0; $n < @{$options}; $n += 2 ) {
        my $checked = ( (grep { $$options[$n] eq $_ } @{$checkarray}) ? 'selected="selected"' : '' );
        $temp .= "<option value=\"$$options[$n]\" $checked>" . ( $length ne '' ? substr($$options[$n + 1],0, $length): $$options[$n+1] ) . "</option>\n";
    }

    return $temp;
}

sub fill_select {
    my ( $log, $dbh, $search, $length, @checkarray ) = @_;
    my @search_data = sql_statement( $log, $dbh, $search );
    return make_select( \@search_data, \@checkarray, $length );
}

sub return_states_and_provinces {
    my @states_and_provinces = ();
    push @states_and_provinces, @provinces::provinces;
    push @states_and_provinces, @states::states;
    return make_select( \@states_and_provinces, \@_ );
}

sub return_states    { return make_drop_down(\@states::states,       shift ) }
sub return_provinces { return make_drop_down(\@provinces::provinces, shift ) }
sub return_countries { return make_select(   \@countries::countries, \@_   ) }

use constant MONTHS => qw( January    February  March     April
                           May        June     July      August
                           September  October  November  December );

sub getyears {
    my ( $startyear, $numyears, $selected ) = @_;
    my $years = q{};

    $startyear = (localtime(time))[5] + 1900 if !$startyear;
    $numyears  = 5 if !$numyears;

    foreach my $year ( $startyear .. $startyear + $numyears ) {
        my $chosen = $selected == $year ? "selected='selected'" : '';
        $years .= "<option value='$year' $chosen>$year</option>\n";
    }

    return $years;
}

# Takes a selected month as an integer (between 1 and 12) and returns all the
# months as HTML <select> dropdown <option>s with the input selected.
sub getmonths {
    my $selected = shift;
    my $months;

    # Either the month is a valid selection or it's not defined (for just
    # populating the drop box).
    die "Selected month must be between 1 and 12\n"
        unless  ($selected >= 1 && $selected <= 12)
              or (not defined $selected or $selected eq '');

    $months .= sprintf qq|<option value="%02d"%s>%s</option>\n|,
                  $_,
                  ($selected == $_) ? ' selected' : '',
                  (MONTHS)[$_ - 1]
    for 1..12;

    return $months;
}

sub getdays {
    my ( $selected ) = @_;

    my $days = q{};

    foreach my $day ( 1 .. 31 ) {
        my $chosen = $selected == $day ? "selected='selected'" : '';
        $days .= "<option value='$day' $chosen>$day</option>\n";
    }

    return $days;
}

sub getemployee_numbers {
    my ( $r, $log, $dbh, $selected ) = @_;
    my ( $temp, $employees );

    $_ = "SELECT * from tbl_Employee_Numbers";
    my @results = sql_statement( $log, $dbh, $_ );
    for ( my $index = 0; $index < @results; $index += 3 ) {
        if ( $results[$index] eq $selected ) {
            $employees .= "<option value=\"$results[$index]\" selected>";
        } else {
            $employees .= "<option value=\"$results[$index]\">";
        }

        $employees .= get_range_text($results[$index+1],$results[$index+2]);
        $employees .= "</option>\n";
    }

    return $employees;
}

sub getannual_sales {
    my ( $r, $log, $dbh, $selected ) = @_;
    my ( $temp, $employees );

    $temp = "SELECT lngIndex,dblMin,dblMax from tbl_Annual_Sales ORDER BY lngIndex";
    my @results = sql_statement( $log, $dbh, $temp );
    for ( my $index = 0; $index < @results; $index += 3 ) {
        if ( $results[$index] eq $selected ) {
            $employees .= "<option value=\"$results[$index]\" selected>";
        }
        else {
            $employees .= "<option value=\"$results[$index]\">";
        }

        $employees .= get_range_text($results[$index+1],$results[$index+2]);
        $employees .= "</option>\n";
    } #end for

    return $employees;
}

sub get_range_text {
    my ( $min, $max ) = @_;

    return ($min eq q{}                ? 'Under '   : $min)
         . ($max ne q{} && $min ne q{} ? ' - '      : q{} )
         . ($max eq q{}                ? ' or more' : $max);
}

sub get_dates {
    my ( $r, $log, $dbh, $variable ) = @_;
    get_start_end_dates(
        $log, $dbh, $variable,
        $r->param('ddmStartYear')  || undef,
        $r->param('ddmStartMonth') || undef,
        $r->param('ddmStartDay')   || undef,
        $r->param('ddmEndYear')    || undef,
        $r->param('ddmEndMonth')   || undef,
        $r->param('ddmEndDay')     || undef,
    );
}


sub get_start_end_dates {
    my ( $log, $dbh, $variable, $startYear, $startMonth, $startDay, $endYear,
         $endMonth, $endDay ) = @_;

    my @current_date = localtime(time);

    my ($start) = configuration::get_value( $log, $dbh, 'startYear' );

    # Holy ambiguous Batman!
    $start = 2002 if !$start;

    $startYear  ||= $current_date[5] + 1900;
    $startMonth ||= $current_date[4] +    1;
    $endYear    ||= $current_date[5] + 1900;
    $endMonth   ||= $current_date[4] +    1;

    $startDay   ||= 1;
    $endDay     ||= Days_in_Month($endYear, $endMonth);

    $startDay     = min $startDay, Days_in_Month($startYear, $startMonth);
    $endDay       = min $endDay,   Days_in_Month($endYear,   $endMonth  );

    # Oh so ugly...
    my @assignment_map = (
        [qw( ddmStartYear  startyears  )],
        [qw( ddmEndYear    endyears    )],
        [qw( ddmStartMonth startmonths )],
        [qw( ddmEndMonth   endmonths   )],
        [qw( ddmStartDay   startdays   )],
        [qw( ddmEndDay     enddays     )],
    );

    $variable->{ddmStartYear} = getyears(
        $start, $current_date[5] - 101, $startYear
    );

    $variable->{ddmEndYear} = getyears(
        $start, $current_date[5] - 101, $endYear
    );

    $variable->{ddmStartMonth} = getmonths($startMonth                 );
    $variable->{ddmEndMonth}   = getmonths($endMonth                   );

    $variable->{ddmStartDay}   = getdays(  $startDay                   );
    $variable->{ddmEndDay}     = getdays(  $endDay || $current_date[3] );

    foreach my $duplicate ( @assignment_map ) {
        $variable->{ $duplicate->[1] } = $variable->{ $duplicate->[0] };
    }

    $variable->{StartDate} = sprintf(
        '%04d-%02d-%02d', $startYear, $startMonth, $startDay
    );

    $variable->{EndDate} = sprintf(
        '%04d-%02d-%02d', $endYear, $endMonth, $endDay || $current_date[3]
    );
}


# If there is any problem, return the original path, so that the original file can be sent.
sub hash_link {
  my ( $path ) = @_;


  my $r = session::r;
  my $log = session::log;
  my $skin_path = $r->dir_config('SkinPath');

  my $src;
  if ( -e $path ) {
    $src = $path;
  } elsif ( $skin_path and -e $skin_path.$path ) {
    $src = $skin_path.$path;
  } elsif ( -e $ENV{DOCUMENT_ROOT}.$path ) {
    $src = $ENV{DOCUMENT_ROOT}.$path;
  } else {
    return $path;
  } # end if

  require JSON;
  require Digest::MD5;

  my $cache_dir = $r->dir_config('cache_dir') ? $r->dir_config('cache_dir') : $skin_path.'/cache';
  return $path if ! $cache_dir;

  my $script;
  if ( ( ! $hash_cache ) and -f $cache_dir.'/config.json' ) {
    $_ = File::Slurp::read_file($cache_dir.'/config.json');
    if ( $_ ) {
      $hash_cache = JSON::from_json( $_ );
      $hash_cache = {} if ! $hash_cache;
    } else {
      $log->error("No content of $cache_dir/config.json");
      $hash_cache = {};
    } # end if
  } # end if

  if ( !($script = $$hash_cache{$path})
      || ! -f $$script{cache_file}
      || ( ( my $timestamp = (stat $src)[9] ) > $script->{timestamp} )
     ) {

    $timestamp = (stat $src)[9] if ! $timestamp;

    my ($base, $dir, $ext) = File::Basename::fileparse($src, qr/\.[^.]+/);
    $ext =~ s/^\.//;
    my $blob = File::Slurp::read_file($src);

    if (!DEBUG) {
      if ( $ext eq 'js' ) {
       eval {
         require JavaScript::Minifier::XS;
         $blob = &JavaScript::Minifier::XS::minify( $blob );
       };
       $log->error( "Eval error of (minify), Reason: " . $@ ) if $@;

     } elsif ( $ext eq 'css' ) {
       eval {
         require CSS::Minifier;
         $blob = &CSS::Minifier::minify( input=>$blob );
       };
       $log->error( "Eval error of (minify), Reason: " . $@ ) if $@;
      } # end if
    } # end if

    my $hash = Digest::MD5::md5_hex($blob);
    $$hash_cache{$path} = $script = {
      src     =>  $src,
      name    => "$base-$hash.$ext",
      path    => $path,
      cache_file  => "$cache_dir/$base-$hash.$ext",
      hash    => $hash,
      timestamp => $timestamp,
    };
    if ( ! -f $$script{cache_file} ) {
      mkdir $cache_dir;
      if ( ! File::Slurp::write_file($script->{cache_file},       { atomic => 1, err_mode=>'carp' }, \$blob) ) {
        $log->error( "couldn't cache $script->{cache_file}" );
        return $path;
      } # end if
      `gzip -c -9 "$$script{cache_file}" > "$$script{cache_file}.gz"`;
      File::Slurp::write_file($cache_dir.'/config.json', { atomic => 1, err_mode=>'carp' },
        JSON::to_json($hash_cache, {pretty => 1})) or warn "Couldn't save cache control file";
    } # end if
  #} else {
    #my @stat = stat $script->{src};

#$log->debug("HASH CACHED $path ($$script{cache_file} ($timestamp) ($$script{timestamp}) @stat");
  } # end if

  # cache_path is the url part
  return '/cache/'.$script->{name};
} # end sub hash_link

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
        `, $name, $value, $label, (($value eq $selected)?'checked="checked"':''),
        join(' ', map { $_.'="'.$$options{$_}.'"' } keys %{$options}),
        $id,
        ( ($$options{inline} or ! exists $$options{inline} ) ? '-inline' : '' ),
        );
    $html .= $$container[1] if $container;
  } # end foreach value
  return $html;
} # end sub radio

sub checked {
  if ( $_[0] ) {
    return 'checked="checked"';
  } # end if
  return '';
} # end sub checked

sub button {
  my ( $name, $options ) = @_;

  my $r = session::r;
  my $log = session::log;
  if ( $$options{href} ) {
    my ( $href ) = $$options{href} =~ /^([^\?]+)/;
    #if ( ! ( $href =~ /^\// ) ) {
# Use a path relative to the current page
    #my $path = $variable{uri};
    #$path =~ s/(.*\/).*/$1/;
    #$href = $path . $href;
    #} # end if
    #my $PageSetting = openprint::Page_Setting::get($href);
    #return if $PageSetting and ! $PageSetting->can_view();
    if ( ! $$options{onclick} ) {
      $$options{onclick} = 'window.location.href=\''.$$options{href}.'\';return false;';
      delete $$options{href};
      $$options{type} = 'button';
    }
  } elsif ( ! $$options{type} ) {
    # Default non-a types to a button
    $$options{type} = 'button';
  } # end if
  $$options{text} = $$options{value} if ! $$options{text};
  $$options{text} = $name if ! $$options{text};
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
  $html .= $$options{text};
  $html .= $$options{type} ? '</button>
' : '</a>
';
  if ( $$options{onclick} ) {
    $html .= '<script'.($r->dir_config('CSP_NONCE') ?' nonce="'.$r->dir_config('CSP_NONCE').'"':'').">
    document.getElementById('Button$name').onclick = function(){
    $$options{onclick};
    };
    </script>
    ";
    delete $$options{onclick};
  } # end if

  return $html;
} # end sub button

my %make_dropdown_options = map { $_=>$_} ('prepend','append','encode','length');

sub select( $$$ ) {
  my ( $data, $selected, $options ) = @_;
  my $html = '<select' . join(' ', '', map { exists $make_dropdown_options{$_} ? () : $_.'="'.$$options{$_}.'"' } keys %{$options} ) . '>';
  $html .= make_drop_down( $data, $selected, $options );
  $html .= '</select>';
} # end sub select($$$)

sub checkboxes {
  my ( $name, $values, $selected, $options ) = @_;

  my $onclick = $$options{onclick} if $options;
  my $html;
  my @container = @{$$options{container}} if $$options{container};
  my %selected = map {$_, $_} @{$selected};

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
', $name, $value, $id, (exists $selected{$value} ? 'checked="checked"' : ''),
( $onclick ? ' onclick="'.$onclick.'"' : ''),
$label,
( $$options{inline} ? '-inline' : '' ),
 );
    } else {
      $html .= sprintf('<input type="checkbox" name="%1$s" value="%2$s" id="%3$s%2$s" %4$s%5$s/>',
          $name, $value, $id,
          (exists $selected{$value} ? 'checked="checked"' : ''),
          ( $onclick ? ' onclick="'.$onclick.'"' : ''), );
    } # end if has label content
    $html .= $container[1] if @container;
  } # end foreach value
  return $html;
} # end sub checkboxes

my @input_options = ( 'type','name','id','onblur','onfocus','onkeyup','onkeypress', 'onkeydown','onchange','class','pattern','ontouch','min','max', 'step', 'placeholder', 'oninput', 'title', 'decimalplaces', 'style', 'data_on_input','data-on-input', 'data_oninput_this' );

sub input {
  my %options = @_;
  my $html = '<input';
  if ( $options{type} eq 'cardinal' ) {
    $options{step} = '1' if ! exists $options{step};
    if ( $ENV{HTTP_USER_AGENT} =~ /ip(ad|od|hone)/i ) {
      $options{type} = 'text';
      $options{pattern} = '[0-9]*' if ! $options{pattern};
    } elsif ( $ENV{HTTP_USER_AGENT} =~ /Firefox/ ) {
      $options{type} = 'text';
      $options{pattern} = '[0-9]*' if ! $options{pattern};
      delete $options{step};
    } else {
      $options{type} = 'number';
    } # end if
    $options{filter} = 'cardinalize(this);' if ! $options{filter};
    $options{oninput} = $options{filter}.$options{oninput};
    #$options{oninput} = 'this.onkeyup.call(this);' if ! $options{oninput};
  } elsif ( $options{type} eq 'integer' ) {
    if ( $ENV{HTTP_USER_AGENT} =~ /ip(ad|od|hone)/i ) {
      $options{type} = 'text';
      $options{pattern} = '^-?\d*' if ! $options{pattern};
    } elsif ( $ENV{HTTP_USER_AGENT} =~ /Firefox/ ) {
      $options{type} = 'text';
      $options{pattern} = '^-?\d*' if ! $options{pattern};
      delete $options{step};
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
    } elsif ( $ENV{HTTP_USER_AGENT} =~ /Firefox/ ) {
      $options{type} = 'text';
      $options{pattern} = '^[\+\-]?[.0-9eE]*' if ! $options{pattern};
      delete $options{step};
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

my %html_replacements = (
  '&' =>  '&amp;',
  '"' =>  '&quot;',
  '<' =>  '&lt;',
  '>' =>  '&gt;',
);
my $replacement_string = join '', keys %html_replacements;
sub html_escape {
  my $thing = $_[0];

  $thing =~ s/([\Q$replacement_string\E])/$html_replacements{$1}/g;
  return $thing;
}
sub slurp_content {
  my ( $file ) = @_;

#$log->debug("Slurping file $file");

  if ( ! ( $file =~ /^\// ) ) {
    # Use a path relative to the current page
    my $path = $variable{uri};
    $path =~ s/(.*\/).*/$1/;
    $file = $path . $file;
  } # end if
  my $content = '';
  if ( -e $config{SkinPath}.$file ) {
    $content = File::Slurp::read_file($config{SkinPath}.$file, err_mode => 'carp' );
  } elsif ( -e $config{SkinPath}.'/html/'.$file ) {
    $content = File::Slurp::read_file($config{SkinPath}.'/html/'.$file, err_mode => 'carp' );
  } elsif ( $ENV{DOCUMENT_ROOT} and ( -e ($ENV{DOCUMENT_ROOT}.$file) ) ) {
    $content = File::Slurp::read_file($ENV{DOCUMENT_ROOT}.$file, err_mode => 'carp' );
  } elsif ( $config{DOCUMENT_ROOT} and ( -e $config{DOCUMENT_ROOT}.$file ) ) {
    $content = File::Slurp::read_file($config{DOCUMENT_ROOT}.$file, err_mode => 'carp' );
  } else {
    $content = File::Slurp::read_file($file, err_mode => 'carp');
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
  return variable_substitution( $r, $log, $dbh, $content, $variable );
} # end sub include

sub save_params {
  my ( $url, @keys ) = @_;
  return if !%param;

  foreach ( @keys ) {
    $log->debug('save_params: key '.$_) if DEBUG;
    if (!exists $param{$_}) {
      $log->debug('save_params: does not exist in param key '.$_) if DEBUG;
      undef($session{$url.'?'.$_});
      next;
    }
    if (ref $param{$_} eq 'ARRAY') {
      $session{"$url?$_"} = join(',', @{$param{$_}} );
$log->debug("Storing ARRAY ($_) (".$session{"$url?$_"}.")") if DEBUG;
    } else {
      s/^\s+//, s/\s+$// for $param{$_};
      $session{$url.'?'.$_} = $param{$_};
$log->debug("Storing ($_) (".$session{"$url?$_"}.")") if DEBUG;
    } # end if
    $session{$url.'?lastupdated'} = time;
  } # end foreach
} # end sub save_params

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

sub include_logs {
  return '';
}

1;
__END__
