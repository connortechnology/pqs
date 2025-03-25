use strict;
package openprint::User_Profile;
require openprint::User_Profile_Entry;
require openprint::Location;

use vars qw( $debug $AUTOLOAD );
$debug = 0;

# Not backed by db, this is an abstract object providing a convenient interface to User_Profile_Fields and Values

sub new {
	my ( $parent, $user_id ) = @_;

	my $self = {};
	bless $self, $parent;
	$$self{user_id} = $user_id;
#$openprint::log->debug("new User_Profile");
	if ( $user_id ) {
		%{$$self{fields}} = map { $_->field(), $_ } openprint::User_Profile_Entry->find(user_id=>$user_id);
	} # end if
#$openprint::log->debug("new User_Profile now listing fields and values");
#foreach my $f ( keys %{$$self{'fields'}} ) {
#$openprint::log->debug("$f => " . $$self{'fields'}{$f}-value() );
#}
	return $self;
} # end sub new

sub AUTOLOAD {
	my $type = ref($_[0]);
	my $name = $AUTOLOAD;
	
	$name =~ s/.*://;
	if ( @_ > 1 ) {
		if ( exists $_[0]{'fields'}{$name} ) {
			return $_[0]{'fields'}{$name}->value( $_[1] );
		} else {
			# create a new entry
		} # end if
	} elsif ( $_[0]{'fields'} and exists $_[0]{'fields'}{$name} ) {
		return $_[0]{'fields'}{$name}->value( );
	} # end if
	#return new openprint::User_Profile_Entry();
	return;
} # end sub AUTOLOAD

sub value {
	if ( ! $_[0]{'fields'} ) {
		%{$_[0]{'fields'}} = map { $_->field(), $_ } openprint::User_Profile_Entry->find('user_id'=>$_[0]{'user_id'}) if $_[0]{'user_id'};
	} # end if

	my ( $Field, $Entry );
	if ( ref $_[1] eq 'openprint::User_Profile_Field' ) {
		$Field = $_[1];
		$Entry = $_[0]{'fields'}{$$Field{'name'}};
	} else {
		$Entry = $_[0]{'fields'}{$_[1]};
		# We don't do the Field here because we only need it when saving
	} # end if

	if ( @_ > 2 ) {
		# Saving
		if ( ! $Entry ) {
			$openprint::log->debug("No entry for $_[1], creating one") if $debug;
			$Entry = new openprint::User_Profile_Entry();
			$Field = openprint::User_Profile_Field->find_one('name'=>$_[1]) if ! $Field;
			$_[0]{'fields'}{$_[1]} = $Entry;
			# We don't set the value, here, so that the next block will make it save
			$Entry->set({ 'field_id' => $Field->id(), 'user_id' => $_[0]{'user_id'} });
			#$openprint::log->debug("After set");
		} # end if
		my $v = ref $_[2] eq 'ARRAY' ? join(',',@{$_[2]}) : $_[2];
		if ( $$Entry{'value'} ne $v ) {
			$_ = $Entry->save( { 'value' => $v } );
		} else {
			$openprint::log->debug("Not saving: $$Entry{'name'} $$Entry{'field'} value: $$Entry{'value'} == $v");
			$openprint::log->debug("@ _ ;: @_ " );
		} # end if
	} # end if 
		
	if ( $Entry ) {
		#$openprint::log->debug("Returning Entry " . $Entry->to_string() );
		return $$Entry{'value'};
	}
	#$openprint::log->debug("Returning No Entry");
	return;
} # end sub value

sub Field {
	if ( ! $_[0]{'fields'} ) {
		%{$_[0]{'fields'}} = map { $_->field(), $_ } openprint::User_Profile_Entry->find('user_id'=>$_[0]{'user_id'}) if $_[0]{'user_id'};
	} # end if

	my $name;
	my $Field;
	if ( ref $_[1] eq 'openprint::User_Profile_Field' ) {
		$name = $_[1]{'name'};
		$Field = $_[1];
	} else {
		$name = $_[1];
	} # end if

	my $Entry = $_[0]{'fields'}{$name};
	if ( ! $Entry ) {
		$Entry = $_[0]{'fields'}{$name} = new openprint::User_Profile_Entry();
		$$Entry{'user_id'} = $_[0]{'user_id'};
		$Field = openprint::User_Profile_Field->find_one('name'=>$name) if ! $Field;
		$Entry->Field( $Field );
	} # end if
	
	return $Entry;
} # end sub Field

sub save {
	my ( $self, $param ) = @_;
	my $error;
#$openprint::log->debug("Saving profile");
	foreach my $Field ( openprint::User_Profile_Field->find('order'=>'sort') ) {
		if ( $Field->type() eq 'date' ) {
			#$openprint::log->debug("Saving a date! $$Field{name} " . join('-', @$param{
                        #'field-'.$Field->id().'_year',
                        #'field-'.$Field->id().'_month',
                        #'field-'.$Field->id().'_day'} ) );
			if ( $$param{'field-'.$Field->id().'_year'} or $$param{'field-'.$Field->id().'_month'} or $$param{'field-'.$Field->id().'_day'} ) {
				$self->value( $Field, join('-', @$param{
							'field-'.$Field->id().'_year',
							'field-'.$Field->id().'_month',
							'field-'.$Field->id().'_day'} ) );
			} # end if
		} elsif ( $Field->type() eq 'location' ) {
			my $prefix = "field-$$Field{id}-";

			foreach ( 'country','state','city','location' ) {
				$$param{$prefix.$_} = openprint::Location->transform('name',$$param{$prefix.$_});
			} # end foreach
			my $parent_id;
			foreach my $region ( 'country','state','province','city' ) {
				if ( $$param{$prefix.$region} ) {
					my $Region = openprint::Location->find_one('name lc'=> lc $$param{$prefix.$region}, 'type'=>$region);
					if ( ! $Region ) {
						$Region = new openprint::Location();
						$error .= $Region->save({'name'=>$$param{$prefix.$region}, 'type'=>$region, 'parent_id'=>$parent_id});
					} # end if
					$$param{$prefix.$region.'_id'} = $Region->id();
				} # end if
				if ( $$param{$prefix.$region.'_id'} ) {
					my $Region = new openprint::Location($$param{$prefix.$region.'_id'});
					if ( $Region->id() ) {
						if ( $parent_id and ! $Region->parent_id() ) {
							$error .= $Region->save({'parent_id'=>$parent_id});
						} # end if
						$parent_id = $$param{$prefix.$region.'_id'};
					} else {
						$openprint::log->error($region.' specified, but not found!?');
					} # end if
				} # end if
			} # end foreach region

			my $Location;
# Now postal code
			if ( $$param{$prefix.'postalcode'} ) {
				my $Place = openprint::Location->find_one( postalcode=>openprint::Location->transform('postalcode', $$param{$prefix.'postalcode'} ), parent_id => $parent_id );
				if ( ! $Place ) {
					$Place = new openprint::Location();
					$error .= $Place->save({
							parent_id=>	$parent_id,
							type=>'place',
							postalcode	=>	$$param{$prefix.'postalcode'},
							});
				} elsif ( $parent_id and ! $Place->parent_id() ) {
					$error .= $Place->save({parent_id=>$parent_id});
				} # end if
				$Location = $Place;
			} else {
				$Location = new openprint::Location($parent_id);
			} # end if
			$self->value( $Field, $Location->id() );	
	
		} elsif ( sets::isin( $Field->type(), [ 'country','state','city' ] ) ) {
			$$param{'field-'.$$Field{id}.'_name'} = openprint::Location->transform('name', $$param{'field-'.$$Field{id}.'_name'});

			if ( $$param{'field-'.$$Field{id}.'_name'} ) {

				# A new one... need to see if it already exists

				# Gets the set value for the parent... so if this is a city, load the field type for a state
				# Needs to do more.  We may be setting the parent in this save request, so it may not exist yet.
				my $parent_id = openprint::Location->transform('parent_id', $self->value( $Field, openprint::Location->parent_type( $Field->type() ) ) );
#$openprint::log->debug("Got parent: $parent_id");


				my $Location = openprint::Location->find_one('type'=>$Field->type(), 'name lc'=>lc $$param{'field-'.$$Field{id}.'_name'}, $parent_id?('parent_id'=>$parent_id):() );
				if ( ! $Location ) {
#$openprint::log->debug("DIdn't find location, so adding it");
					$Location = new openprint::Location();
					$error .= $Location->save({'type'=>$Field->type(),'name'=>$$param{'field-'.$$Field{id}.'_name'}, 
							($parent_id?('parent_id'=>$parent_id):())});
					return $error if $error;
				} # end if
				$self->value( $Field, $Location->id() ) if $Location->id();
			} else {
				$self->value( $Field, $$param{'field-'.$Field->id()} );
			} # end if
		} else {
			$self->value( $Field, $$param{'field-'.$Field->id()} );
		} # end if
	} # end foreach $Field
	return $error;
} # end sub save

1;
__END__
