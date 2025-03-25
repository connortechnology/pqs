use strict;
package openprint::Company_Profile;
require openprint::Company_Profile_Entry;
require openprint::Company_Profile_Field;
require openprint::Location;

use vars qw( $debug $AUTOLOAD );
$debug = 0;

# Not backed by db, this is an abstract object providing a convenient interface to Company_Profile_Fields and Values

sub new {
	my ( $parent, $company_id ) = @_;

	my $self = {};
	bless $self, $parent;
	$$self{company_id} = $company_id;
	%{$$self{Fields}} = map { $$_{name} => $_ } openprint::Company_Profile_Field->find();
	if ( $company_id ) {
		%{$$self{Entries}} = map { $_->field(), $_ } openprint::Company_Profile_Entry->find( company_id=>$company_id );
	} # end if
#$openprint::log->debug("new Company_Profile now listing Entries and values");
#foreach my $f ( keys %{$$self{Entries}} ) {
#$openprint::log->debug("$f => " . $$self{Entries}{$f}-value() );
#}
	return $self;
} # end sub new

sub AUTOLOAD {
	my $self = shift;
	my $type = ref($self);
	my $name = $AUTOLOAD;
	
	$name =~ s/.*://;
	if ( @_ ) {
		if ( exists $$self{Entries}{$name} ) {
			return $$self{Entries}{$name}->value( $_[0] );
		} else {
			# create a new entry
		} # end if
	} elsif ( $$self{Entries} and exists $$self{Entries}{$name} ) {
		return $$self{Entries}{$name}->value( );
	} # end if
	return undef;
} # end sub AUTOLOAD

sub default {
	
	#my $Field = openprint::Company_Profile_Field->find_one( name=>$_[1] );
	my $Field = $_[0]{Fields}{$_[1]};
	$openprint::log->debug("default for $_[1] is $Field");
	return $Field ? $$Field{defaults} : undef;
} 

sub value {
	if ( ! $_[0]{Entries} ) {
		%{$_[0]{Entries}} = map { $_->field(), $_ } openprint::Company_Profile_Entry->find( company_id=>$_[0]{company_id}) if $_[0]{company_id};
	} # end if

	my ( $Field, $Entry );
	if ( ref $_[1] eq 'openprint::Company_Profile_Field' ) {
		$Field = $_[1];
		$Entry = $_[0]{Entries}{$$Field{name}};
	} else {
		$Entry = $_[0]{Entries}{$_[1]};
		# We don't do the Field here because we only need it when saving
	} # end if

	if ( @_ > 2 ) {
		# Saving
		if ( ! $Entry ) {
			$openprint::log->debug("No entry for $_[1], creating one") if $debug;
			$Entry = new openprint::Company_Profile_Entry();
			$Field = openprint::Company_Profile_Field->find_one( name=>$_[1]) if ! $Field;
			$_[0]{Entries}{$_[1]} = $Entry;
			# We don't set the value, here, so that the next block will make it save
			$Entry->set({ field_id => $Field->id(), company_id => $_[0]{company_id} });
			$openprint::log->debug("After set $_[1] => $_[2]") if $debug;
		} # end if
		my $v = ref $_[2] eq 'ARRAY' ? join(',',@{$_[2]}) : $_[2];
		if ( $$Entry{value} ne $v ) {
			$_ = $Entry->save( { value => $v } );
			$openprint::log->warn("Saving " . $Entry->field() . ': value=' . $v . " error: $_ " );
		} else {
			$openprint::log->debug("Not saving: $$Entry{field_id} $_[1] value: $$Entry{value} == $v");
		} # end if
	} # end if 
		
	if ( $Entry ) {
		$openprint::log->debug("Returning Entry " . $Entry->to_string() );
		return $$Entry{value};
	}
	$openprint::log->debug("Returning No Entry for $$Field{name}: params @_") if $debug;
	return undef;
} # end sub value

sub Field {
	if ( ! $_[0]{Entries} ) {
		%{$_[0]{Entries}} = map { $_->field(), $_ } openprint::Company_Profile_Entry->find('company_id'=>$_[0]{company_id}) if $_[0]{company_id};
	} # end if

	my $name;
	my $Field;
	if ( ref $_[1] eq 'openprint::Company_Profile_Field' ) {
		$name = $_[1]{name};
		$Field = $_[1];
	} else {
		$name = $_[1];
	} # end if

	my $Entry = $_[0]{Entries}{$name};
	if ( ! $Entry ) {
		$Entry = $_[0]{Entries}{$name} = new openprint::Company_Profile_Entry();
		$$Entry{company_id} = $_[0]{company_id};
		$Field = openprint::Company_Profile_Field->find_one( name=>$name ) if ! $Field;
		return undef if ! $Field;
		$Entry->Field( $Field );
	} # end if
	
	return $Entry;
} # end sub Field

sub save {
	my ( $self, $param ) = @_;
	my $error;
$openprint::log->debug("Saving profile");
	foreach my $Field ( openprint::Company_Profile_Field->find( order=>'sort' ) ) {
		if ( $Field->type() eq 'date' ) {
			$openprint::log->debug("Saving a date! $$Field{name} " . join('-', @$param{
                        'field-'.$Field->id().'_year',
                        'field-'.$Field->id().'_month',
                        'field-'.$Field->id().'_day'} ) );
			if ( $$param{'field-'.$Field->id().'_year'} or $$param{'field-'.$Field->id().'_month'} or $$param{'field-'.$Field->id().'_day'} ) {
				$self->value( $Field, join('-', @$param{
							'field-'.$Field->id().'_year',
							'field-'.$Field->id().'_month',
							'field-'.$Field->id().'_day'} ) );
			} # end if
		} elsif ( sets::isin( $Field->type(), [ 'country','state','city' ] ) ) {
			if ( $$param{'field-'.$$Field{id}.'_name'} ) {

				# A new one... need to see if it already exists

				# Gets the set value for the parent... so if this is a city, load the field type for a state
				# Needs to do more.  We may be setting the parent in this save request, so it may not exist yet.
				my $parent_id = openprint::Location->transform('parent_id', $self->value( $Field, openprint::Location->parent_type( $Field->type() ) ) );
$openprint::log->debug("Got parent: $parent_id");


				my $Location = openprint::Location->find_one('type'=>$Field->type(), 'name lc'=>lc $$param{'field-'.$$Field{id}.'_name'}, $parent_id?('parent_id'=>$parent_id):() );
				if ( ! $Location ) {
$openprint::log->debug("DIdn't find location, so adding it");
					$Location = new openprint::Location();
					$error .= $Location->save({ type=>$Field->type(), name=>$$param{'field-'.$$Field{id}.'_name'}, 
($parent_id?('parent_id'=>$parent_id):())});
					return $error if $error;
				} # end if
				$self->value( $Field, $Location->id() ) if $Location->id();
			} elsif ( exists $$param{'field-'.$Field->id()} ) {
				$self->value( $Field, $$param{'field-'.$Field->id()} );
			} # end if
		} elsif ( exists $$param{'field-'.$Field->id()} ) {
			$self->value( $Field, $$param{'field-'.$Field->id()} );
		} # end if
	} # end foreach $Field
	return $error;
} # end sub save

sub check {
	my ( $self, $param ) = @_;
	my @errors;
$openprint::log->debug("checking profile");
	foreach my $Field ( openprint::Company_Profile_Field->find( order=>'sort', required=>1 ) ) {
		if ( $Field->type() eq 'date' ) {
			if ( ! Date::Calc::check_date( @$param{map { "field-$$Field{id}_$_" } ( 'year','month','day' ) } ) ) {
				push @errors, $$Field{name};
			} # end if
		} elsif ( sets::isin( $Field->type(), [ 'country','state','city' ] ) ) {
			if ( ! ( $$param{'field-'.$$Field{id}.'_name'} and $$param{'field-'.$Field->id()} ) ) {
				push @errors, $$Field{name};
			} # end if
		} elsif ( ! $$param{'field-'.$Field->id()} ) {
			push @errors, $$Field{name};
		} # end if 
	} # end foreach
	return @errors;
} # end sub check

1;
__END__
