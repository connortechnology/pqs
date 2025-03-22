use strict;
package openprint::Object;
use Time::HiRes qw{ gettimeofday tv_interval };
use Carp qw( cluck );

require openprint;
require sets;
require openprint::Object_Type;
require openprint::Log;
use vars qw( $log $dbh $AUTOLOAD %cache %name_cache %fields %transforms $no_cache %session %config );

*log = \$openprint::log;
*dbh = \$openprint::dbh;
*session = \%openprint::session;
*config = \%openprint::config;

my $debug = 0;
use constant DEBUG_ALL => 0;
use constant DEBUG_CACHE => 0;
use constant DEBUG_LOCKS => 0;
$no_cache = 0;

sub init_cache {
	if ( @_ ) {
		if ( ! $name_cache{$_[0]} ) {
			my @items = $_[0]->find();
      $log->debug('init_cache of '.$_[0].' # of items: '.@items) if DEBUG_CACHE;
			foreach ( @items ) {
				$name_cache{$_[0]}{$$_{$_->cache_field()}} = $_;
			} # end foreach
		} # end if
	} else {
		$no_cache = 0;
		%cache = ();
		%name_cache = ();
	} # end if
} # end sub init_cache

sub debug {
	$log->debug("Dumping Object cache");
	foreach my $o ( keys %cache ) {
		foreach my $id ( keys %{$cache{$o}} ) {
			$log->debug( "$o : $id" );
		} # end foreach
	} # end foreach
	foreach my $object_type ( keys %name_cache ) {
		$log->debug("Name Cach contains $object_type => $name_cache{$object_type}");
		foreach my $k ( keys %{$name_cache{$object_type}} ) {
			$log->debug("Name Cach for $object_type contains $k => $name_cache{$object_type}{$k}");
		}
	}
} # end sub debug

sub new {
	my ( $parent, $id, $data, $dont_cache ) = @_;

	my $ref = ref $id;

	$cache{$parent} = {} if ! $cache{$parent};
	my $sub_cache = $cache{$parent};
#$log->debug("New parent:$parent id:$id data:$data ref:$ref");

	if (!$ref) {
		if ($id and (!$dont_cache) and $$sub_cache{$id}) {
			if ( $data ) {
				my $self = $$sub_cache{$id};
				# The reason to use load is if we have overriden it in the object, like in Paper
        # 2022-04-21 had commented it out for some reason. Probably performance, but we need it if we are using find()
        #$openprint::log->debug("New:loading for $id $$data{id} ($data)");
        $self->load($data);
        #$log->debug("Loading object $parent $id from cache and populating with data new objcet is $self old cache is " . $$sub_cache{$id}) if DEBUG_CACHE;
				return $self;
			} else {
				$log->debug('Loading from cache '.$parent.' '. $id.' = '.$$sub_cache{$id}) if DEBUG_CACHE;
        # If the object is cached
				return $$sub_cache{$id};
			}
		} elsif ( DEBUG_CACHE ) {
			my ( $caller, undef, $line ) = caller;
			#my $self = {};
			#bless $self, $parent;
			#if ( ( $$self{id} = $id ) or $data ) {
#$log->debug("loading $parent $id") if $debug or DEBUG_ALL;
				#$self->load( $data );
			#} # end if
			$log->debug("not cached from $caller:$line no ref, $parent id: $id, dont_cache: ".(defined($dont_cache)?$dont_cache:'undef').' sub '.$sub_cache.' '.$$sub_cache{$id} . ' data '.$data) if $id;
		} # end if
#$log->debug("Not Loading from cache $parent $id") if $id and ! $data;
		my $self = {};
		bless $self, $parent;

if ( 1 ) {
  # Refresh contents from data or db
	if ( ( $$self{id} = $id ) or $data ) {
		if ( $debug or DEBUG_ALL ) {
			my ( $caller, undef, $line ) = caller;
			$log->debug("loading $parent $id from $caller:$line");
		}
		$self->load($data);
	} # end if
}
		if ( ! ( $no_cache or $dont_cache ) ) {
			if ( $id ) {
				# Using $id instead of $$self{id} means that we cache non existent entries
			#if ( $$self{id} ) {
$log->debug("new id_Caching $parent $id = $self") if DEBUG_CACHE or $debug;

				$$sub_cache{$id} = $self;
			} # end if
		} else {
$log->debug("NOT Caching $parent $id = $self") if $debug;
		} # end if
		return $self;
	} elsif ( ref $id eq 'HASH' ) {
		#my $self = {};
		my @keys = keys %{$id};
		bless $id, $parent;
# First off, for now, don't cache figure that out later
		#@$id{@keys} = @$id{@keys};
#$log->debug("New by hash @keys : " . $self->to_string() );
#$log->debug("New by hash @keys : " . $id->to_string() );
		$id->load( $data );
#$log->debug("New by hash @keys : " . $id->to_string() );
		return $id;
	} elsif ( ref $id eq 'ARRAY' and $data ) {
		my $self = {};
		bless $self, $parent;
#$log->debug("Multi-key Obejct @$id @$data{@$id}" );
		@$self{@$id} = @$data{@$id} if @$id;
		$self->load( $data );
#$log->debug( $parent . ': ' .$self->to_string() );
		return $self;
	} # end if ref id
#$log->error("test");
} # end sub new

sub load {
	my ( $self, $data ) = @_;
	my $type = ref $self;
	no strict 'refs';
	my $fields = \%{$type.'::fields'};
	my $debug = ${$type.'::debug'};
	$debug = DEBUG_ALL if ! $debug;
	my $starttime = [gettimeofday] if $debug;
	if ( ! $data ) {
    #$log->debug("Object::load Loading from db $type");
		my $table = ${$type.'::table'};
		if ( ! $table ) {
			$log->error( 'NO table for type ' . $type );
			return;
		} # end if
		my @identified_by = @{$type.'::identified_by'};
		my $d = ${$type.'::dbh'};
		$d = $dbh if ! $d;

		if ( @identified_by ) {
			$log->debug('SELECT * FROM ' . $table . ' WHERE ' . join(' AND ', map { $$fields{$_} . '=' . $$self{$_} } @identified_by ) ) if $debug;
			$data = $d->selectrow_hashref( 'SELECT * FROM ' . $table . ' WHERE ' . join(' AND ', map { $$fields{$_} . '=?' } @identified_by ), {}, @$self{@identified_by} );
			#$log->debug("Got $type: " . join(',', map { $_ . '=>' . $$data{$_} } keys %$data ) ) if $debug;
		} elsif ( exists $$fields{id} ) {
			$log->debug("SELECT * FROM $table WHERE $$fields{id}=$$self{id}" ) if $debug;
			$data = $d->selectrow_hashref('SELECT * FROM '.$table.' WHERE '.$$fields{id}.'=?', {}, $$self{id});
    } else {
      $log->error("No ability to identify object");
		} # end if
		if ( ! $data ) {
			if ( $d->errstr ) {
				$log->error("Failure to load $type $$self{id}: Reason: ".$d->errstr);
				Carp::cluck("Failure to load $type $$self{id}: Reason: ".$d->errstr);
			} elsif ( $debug ) {
				$log->debug("Failure to load $type $$self{id}: Reason: ");
			} # end if
			delete $$self{id};
			if ( @identified_by ) {
				delete @$self{@identified_by};
			} # end if
		#} elsif ( $debug ) {
			#$log->debug("Got $type: " . join(',', map { $_ . '=>' . $$data{$_} } keys %$data ) . ' in ' . sprintf('%.4f', tv_interval($starttime)*1000) .' useconds' );
		} # end if
	} # end if

	if ( $data and %$data ) {
		my %keys = map { (defined $$fields{$_} ? ($_=>$$fields{$_}) : (exists $$data{$_} ? ($_=>$_) : ()) ) } keys %$fields;
    #$log->debug(join(',', map { $_ .'=>'.$keys{$_} } sort { $a cmp $b} keys %keys)) if $debug;
		@$self{keys %keys} = @$data{ values %keys };
  } else {
    $log->warn('No data for ? '.$self->to_string() . ' ref data: '.ref $data);
	} # end if
} # end sub load

sub save {
	my ( $self, $data, $force_insert ) = @_;

	my $type = ref $self;
	if (!$type) {
		my ($caller, undef, $line) = caller;
		$log->error('No type in Object::save. self:'.$self.' from '.$caller.':'.$line);
	}
	my $local_dbh = eval '$'.$type.'::dbh';
	$local_dbh = $openprint::dbh if ! $local_dbh;
	$self->set($data ? $data : {});
	if ($debug or DEBUG_ALL) {
		if ($data) {
			foreach my $k ( keys %$data ) {
				$log->debug('Object::save after set '.join(' ', $k, '=>',
							(defined($$data{$k})?$$data{$k}:'undef'),
							(defined($$self{$k})?$$self{$k}:'undef')
							) );
			}
		} else {
			$log->debug('No data after set');
		}
	} # end if DEBUG

	my $table = eval('$'.$type.'::table');
	my $fields = eval('\%'.$type.'::fields');
	my $debug = eval('$'.$type.'::debug');
	$debug = DEBUG_ALL if ! $debug;

  # copy all the sql backed fields, as there might be other things in the object.
	my %sql;
  my @keys = map { defined $$fields{$_} ? $_ : () } keys %$fields;
  @sql{@$fields{@keys}} = @$self{@keys};

	if ( !$force_insert ) {
		$sql{$$fields{updated_by}} = $openprint::session{user_id} if exists $$fields{updated_by};
		$sql{$$fields{updated_on}} = 'NOW()' if exists $$fields{updated_on};
	} # end if
	my $serial = eval '$'.$type.'::serial';
	my @identified_by = eval '@'.$type.'::identified_by';

	my $ac = sql::start_transaction( $local_dbh );
	if ( ! $serial ) {
		my $insert = $force_insert;
		my %serial = eval('%'.$type.'::serial');
		if ( ! %serial ) {
#$log->debug('No serial') if $debug;
			# No serial columns defined, which means that we will do saving by delete/insert instead of insert/update
			if ( @identified_by ) {
				my $where = join(' AND ', map { $$fields{$_}.'=?' } @identified_by );
				if ( $debug ) {
					$log->debug("DELETE FROM $table WHERE $where");
				} # end if

				if ( ! ( ( $_ = $local_dbh->prepare("DELETE FROM $table WHERE $where") ) and $_->execute( @$self{@identified_by} ) ) ) {
					$where =~ s/\?/\%s/g;
					$log->error("Error deleting: DELETE FROM $table WHERE " .  sprintf($where, map { defined $_ ? $_ : 'undef' } ( @$self{@identified_by}) ).'):' . $local_dbh->errstr);
					$local_dbh->rollback();
					sql::end_transaction( $local_dbh, $ac );
					return $local_dbh->errstr;
				} elsif ( $debug ) {
					$log->debug("SQL succesful DELETE FROM $table WHERE $where");
				} # end if
			} # end if
			$insert = 1;
		} else {
			foreach my $id ( @identified_by ) {
				if ( ! $serial{$id} ) {
					#my ( $caller, undef, $line ) = caller;
					#$log->debug("$id nor in serial for $type from $caller:$line") if $debug;
					next;
				}
				if ( ! $$self{$id} ) {
					($$self{$id}) = ($sql{$$fields{$id}}) = $local_dbh->selectrow_array( q{SELECT nextval('} . $serial{$id} . q{')} );
					$log->debug("SQL statement execution SELECT nextval('$serial{$id}') returned $$self{$id}") if $debug or DEBUG_ALL;
					$insert = 1;
				} # end if
			} # end foreach
		} # end if ! %serial

		if ( $insert ) {
			my @keys = keys %sql;
			my $command = "INSERT INTO $table (" . join(',', @keys ) . ') VALUES (' . join(',', map { '?' } @sql{@keys} ) . ')';
			if ( ! ( ( $_ = $local_dbh->prepare($command) ) and $_->execute( @sql{@keys} ) ) ) {
				my $error = $local_dbh->errstr;
				$command =~ s/\?/\%s/g;
				$log->error('SQL statement execution failed: ('.sprintf($command, , map { defined $_ ? $_ : 'undef' } ( @sql{@keys}) ).'):' . $local_dbh->errstr);
				$local_dbh->rollback();
				sql::end_transaction( $local_dbh, $ac );
				return $error;
			} # end if
			if ( $debug or DEBUG_ALL ) {
				$command =~ s/\?/\%s/g;
				$log->debug('SQL statement execution: ('.sprintf($command, , map { defined $_ ? $_ : 'undef' } ( @sql{@keys} ) ).'):' );
			} # end if
		} else {
			my @keys = keys %sql;
			my $command = 'UPDATE '.$table.' SET ' . join(',', map { $_ . ' = ?' } @keys ) . ' WHERE ' . join(' AND ', map { $_ . ' = ?' } @$fields{@identified_by} );
			if ( ! ( $_ = $local_dbh->prepare($command) and $_->execute( @sql{@keys,@$fields{@identified_by}} ) ) ) {
				my $error = $local_dbh->errstr;
				$command =~ s/\?/\%s/g;
				$log->error('SQL failed: ('.sprintf($command, map { defined $_ ? $_ : 'undef' } ( @sql{@keys, @$fields{@identified_by}}) ).'):' . $local_dbh->errstr);
				$local_dbh->rollback();
				sql::end_transaction( $local_dbh, $ac );
				return $error;
			} # end if
			if ( $debug or DEBUG_ALL ) {
				$command =~ s/\?/\%s/g;
				$log->debug('SQL DEBUG: ('.sprintf($command, map { defined $_ ? $_ : 'undef' } ( @sql{@keys,@$fields{@identified_by}} ) ).'):' );
			} # end if
		} # end if
	} else { # not identified_by
		@identified_by = ('id') if ! @identified_by;
		my $need_serial = ! ( @identified_by == map { $$self{$_} ? $_ : () } @identified_by );

		if ($force_insert or $need_serial) {
			if ( $need_serial ) {
				if ( $serial ) {
					@$self{@identified_by} = @sql{@$fields{@identified_by}} = $local_dbh->selectrow_array( q{SELECT nextval('} . $serial . q{')} );
					if ( $local_dbh->errstr() )  {
						$log->error('Error getting next id. ' . $local_dbh->errstr() );
						$log->error("SQL statement execution SELECT nextval('$serial') returned ".join(',', @$self{@identified_by}));
					} elsif ( $debug or DEBUG_ALL ) {
						$log->debug("SQL statement execution SELECT nextval('$serial') returned ".join(',', @$self{@identified_by}));
					} # end if
				} # end if
			} # end if
			my @keys = keys %sql;
			my $command = "INSERT INTO $table (" . join(',', @keys ) . ') VALUES (' . join(',', map { '?' } @sql{@keys} ) . ')';
			if ( ! ( $_ = $local_dbh->prepare($command) and $_->execute( @sql{@keys} ) ) ) {
				$command =~ s/\?/\%s/g;
				my $error = $local_dbh->errstr;
				$log->error('SQL failed: ('.sprintf($command, map { defined $_ ? $_ : 'undef' } ( @sql{@keys}) ).'):' . $error);
				$local_dbh->rollback();
				sql::end_transaction( $local_dbh, $ac );
				return $error;
			} # end if
			if ( $debug or DEBUG_ALL ) {
				$command =~ s/\?/\%s/g;
				$log->debug('SQL DEBUG: ('.sprintf($command, map { defined $_ ? $_ : 'undef' } ( @sql{@keys} ) ).'):' );
			} # end if
		} else {
			delete $sql{created_on};
			my @keys = keys %sql;
			@keys = sets::exclude( [ @$fields{@identified_by} ], \@keys );
			my $command = "UPDATE $table SET " . join(',', map { $_ . ' = ?' } @keys ) . ' WHERE ' . join(' AND ', map { $$fields{$_} .'= ?' } @identified_by );
			if ( ! ( $_ = $local_dbh->prepare($command) and $_->execute( @sql{@keys}, @sql{@$fields{@identified_by}} ) ) ) {
				my $error = $local_dbh->errstr;
				$command =~ s/\?/\%s/g;
				$log->error('SQL failed: ('.sprintf($command, map { defined $_ ? $_ : 'undef' } ( @sql{@keys}, @sql{@$fields{@identified_by}} ) ).'):' . $error) if $log;
				$local_dbh->rollback();
				sql::end_transaction($local_dbh, $ac);
				return $error;
			} # end if
			if ( $debug or DEBUG_ALL ) {
				$command =~ s/\?/\%s/g;
				$log->debug('SQL DEBUG: ('.sprintf($command, map { defined $_ ? ( ref $_ eq 'ARRAY' ? join(',',@{$_}) : $_ ) : 'undef' } ( @sql{@keys}, @$self{@identified_by} ) ).'):' );
			} # end if
		} # end if
	} # end if
	sql::end_transaction( $local_dbh, $ac );
  # This is wasteful. Might be needed to pick up default values but that seems like a bad idea.
  # Need it to deal with NOW() etc.  agree it's wasteful. Perhaps we need to detect when it is needed.
  $self->load();
	if ( $$fields{id} ) {
    if ( ! $openprint::Object::cache{$type}{$$self{id}} ) {
			$openprint::Object::cache{$type}{$$self{id}} = $self;
    } # end if
	} # end if

  # Isn't this inefficient?
	eval 'if ( %'.$type.'::find_cache ) { %'.$type.'::find_cache = (); }';
  if (0 and $serial) {
    if ($type !~ /Log/i) {
      my ( $caller, undef, $line ) = caller;
      if ( $caller ne 'openprint::Log' ) {
        (new openprint::Log())->save({Object=>$self, action=>($$self{id} ? 'Saved' : 'Created')});
      }
    }
  }
	return '';
} # end sub save

sub get {
	my $self = shift;
	return map { $self->$_() } @_;
} # end sub get

sub changes {
	my ( $self, $params ) = @_;

	my $type = ref $self;
	if ( ! $type ) {
		my ( $caller, undef, $line ) = caller;
		$log->error("No type in Object::changes. self:$self from  $caller:$line");
	}
	my $fields = eval ('\%'.$type.'::fields');
	if ( ! $fields ) {
$log->warn('Object::changes called on an object with no fields');
		return;
	} # end if
	#my %defaults = eval('%'.$type.'::defaults');
	my @results;

	foreach my $field ( sort keys %$fields ) {
		if ( ! exists $$params{$field} ) {
			$log->debug("$field does not exist in params") if $debug;
			next;
		}
		if ( ref $$self{$field} eq 'ARRAY'  ) {
      my @new_value = (ref $$params{$field} eq 'ARRAY' ? @{$$params{$field}} : ( $$params{$field} ));
      my @intersection = sets::intersection(@{$$self{$field}}, @new_value);
			if ( @{$$self{$field}} != @intersection or @new_value != @intersection) {
				push @results, $field.' changed from '.join(',',@{$$self{$field}}).' to '.join(',', @new_value);
      } elsif ( $debug ) {
        $log->debug( "$field not changed from ".join(',',@{$$self{$field}}).' to '.join(',', @new_value).' intersection:'.join(',',sets::intersection(@{$$self{$field}}, @new_value)));
			}
		} else {
      my $newvalue = $self->transform($field=>$$params{$field});
      if ( $$self{$field} ne $newvalue ) {
        if ( $field eq 'password' ) {
          push @results, "$field changed";
        } else {
          push @results, $field.' changed from \''.$$self{$field}.'\' to \''.$newvalue.'\'';
        }
      } else {
        if ( $debug ) {
          $log->debug("$field eq $$self{$field} to $newvalue");
        }
      } # end if
		} # end if
	} # end foreach field
	return @results;
}
sub set_no_defaults {
  my ( $self, $params ) = @_;
  my @set_fields = ();

  my $type = ref $self;
  if ( ! $type ) {
    my ( $caller, undef, $line ) = caller;
    $log->error("No type in Object::set. self:$self from  $caller:$line");
  }
  my %fields = eval ('%'.$type.'::fields');
  if ( ! %fields ) {
    $log->warn('Object::set called on an object with no fields');
  } # end if
  my %defaults = eval('%'.$type.'::defaults');
  if ( ref $params ne 'HASH' ) {
    my ( $caller, undef, $line ) = caller;
    $openprint::log->error("$type -> set called with non-hash params from $caller $line");
  }

  foreach my $field ( keys %fields ) {
    $log->debug("field: $field, param: ".$$params{$field}) if $debug;
    if ( exists $$params{$field} ) {
      $openprint::log->debug("field: $field, $$self{$field} =? param: ".$$params{$field}) if $debug;
      if ( ( ! defined $$self{$field} ) or (!defined($$params{$field})) or ($$self{$field} ne $params->{$field}) ) {
        # Only make changes to fields that have changed
        if ( defined $fields{$field} ) {
          $$self{$field} = $$params{$field} if defined $fields{$field};
          push @set_fields, $fields{$field}, $$params{$field};  #mark for sql updating
        } # end if
        $openprint::log->debug("Running $field with $$params{$field}") if $debug;
        if ( my $func = $self->can( $field ) ) {
          $func->( $self, $$params{$field} );
        } # end if
      } # end if
    } # end if

    if ( defined $fields{$field} ) {
      if ( $$self{$field} ) {
        $$self{$field} = transform( $type, $field, $$self{$field} );
      } # end if $$self{field}
    }
  } # end foreach field# end sub changes
}

sub set {
	my ( $self, $params ) = @_;
	my @set_fields = ();

	my $type = ref $self;
	if ( ! $type ) {
		my ( $caller, undef, $line ) = caller;
		$log->error("No type in Object::set. self:$self from  $caller:$line");
	}
	my %fields = eval('%'.$type.'::fields');
	if ( ! %fields ) {
		$log->warn('Object::set called on an object with no fields');
	} # end if
	my %defaults = eval('%'.$type.'::defaults');
	if ( ref $params ne 'HASH' ) {
		my ( $caller, undef, $line ) = caller;
		$openprint::log->error("$type -> set called with non-hash params from $caller $line");
	}

	foreach my $field ( keys %fields ) {
$log->debug("field: $field, param: ".(defined $$params{$field} ? $$params{$field} : 'undef')) if $debug;
		if ( exists $$params{$field} ) {
$openprint::log->debug("field: $field, $$self{$field} =? param: ".$$params{$field}) if $debug;
			if ( ( ! defined $$self{$field} ) or (!defined($$params{$field})) or ($$self{$field} ne $params->{$field}) ) {
# Only make changes to fields that have changed
				if ( defined $fields{$field} ) {
					$$self{$field} = $$params{$field} if defined $fields{$field};
					push @set_fields, $fields{$field}, $$params{$field};	#mark for sql updating
				} # end if
$openprint::log->debug("Running $field with $$params{$field}") if $debug;
				if ( my $func = $self->can( $field ) ) {
					$func->( $self, $$params{$field} );
				} # end if
			} # end if
		} # end if

		if ( defined $fields{$field} ) {
			if ( $$self{$field} ) {
				$$self{$field} = transform($type, $field, $$self{$field});
			} # end if $$self{field}
		}
	} # end foreach field

	foreach my $field ( keys %defaults ) {

		if ( ( ! exists $$self{$field} ) or (!defined $$self{$field}) or ( $$self{$field} eq '' ) ) {
			$log->debug("Setting default ($field) ($$self{$field}) ($defaults{$field}) ") if $debug;
			if ( defined $defaults{$field} ) {
				$log->debug("Default $field is defined: $defaults{$field}") if $debug;
				if ( $defaults{$field} eq 'NOW()' ) {
					$$self{$field} = 'NOW()';
				} else {
					$$self{$field} = eval($defaults{$field});
					$log->error( "Eval error of object default $field default ($defaults{$field}) Reason: " . $@ ) if $@;
				} # end if
			} else {
				$$self{$field} = $defaults{$field};
			} # end if
#$$self{$field} = ( defined $defaults{$field} ) ? eval($defaults{$field}) : $defaults{$field};
			$log->debug("Setting default for ($field) using ($defaults{$field}) to ($$self{$field}) ") if $debug;
		} # end if
	} # end foreach default
	return @set_fields;
} # end sub set

sub copy {
	no strict 'refs';
	my $type = ref $_[0];
	my $new = new $type;
	my $fields = \%{$type.'::fields'};
	@$new{keys %$fields} = @{$_[0]}{keys %$fields};
	delete $$new{id};
	delete $$new{album_id};

	return $new;
} # end sub copy

sub clone {
	my $new = {};
	bless $new, ref $_[0];
	my @keys = keys %{$_[0]};
	@$new{@keys} = @{$_[0]}{@keys};
	return $new;
} # end sub clone

sub delete {
	my ( $self ) = @_;
	my $type = ref $self;
	if ( ! $type ) {
		my ( $caller, undef, $line ) = caller;
		$log->error("No type in Object::delete. self:$self from  $caller:$line");
	}

	my $table = eval '$'.$type.'::table';
	my $debug = eval '$'.$type.'::debug';
	my %fields = eval '%'.$type.'::fields';
	my @identified_by = eval '@'.$type.'::identified_by';
	@identified_by = ( 'id' ) if ! @identified_by;
	if ( ! $$self{$identified_by[0]} ) {
		$log->error("Called delete on object with no id (@identified_by) of type $type : " . $self->to_string());
		return 'Object::delete: No id in object: ' . $self->to_string();
	} # end if

	my $local_dbh = eval '$'.$type.'::dbh';
	$local_dbh = $openprint::dbh if ! $local_dbh;

	my $where = join(' AND ', map { $fields{$_}.'=?' } @identified_by );
	if ( exists $fields{deleted} ) {
		sql::update( undef, $local_dbh, $table, [$where, @$self{@identified_by}], 'deleted', 1 );
		return $local_dbh->errstr if $local_dbh->errstr;
		$$self{deleted}=1;
		(new openprint::Log())->save({Object=>$self,action=>'Delete'}) if $type ne 'openprint::Log';
	} else {
		my $rows = $local_dbh->do( 'DELETE FROM '.$table.' WHERE '.$where, undef, @$self{@identified_by} );
		$log->warn("No rows deleted for 'DELETE FROM $table WHERE $where, @$self{@identified_by}") if ! $rows;
		$log->debug("DELETE FROM $table WHERE $where, @$self{@identified_by}") if $debug;

		return $local_dbh->errstr if $local_dbh->errstr;
		delete $openprint::Object::cache{$type}{join('-',@$self{@identified_by})};
		(new openprint::Log())->save({action=>'Delete', note=>$self->to_string()}) if $type ne 'openprint::Log';
	} # end if
	eval 'if ( %'.$type.'::find_cache ) { %'.$type.'::find_cache = (); }';
	return '';
} # end sub delete

sub undelete {
	my $self = shift;
	my $type = ref $self;
	my $table = eval '$'.$type.'::table';
	my %fields = eval '%'.$type.'::fields';
	sql::update( undef, undef, $table, [$fields{id}.'=?', $$self{id}], 'deleted', 0 );
	$$self{deleted} = 0;
	my %find_cache = eval '%'.$type.'::find_cache';
	%find_cache = () if %find_cache;
	delete $openprint::Object::cache{$type}{$$self{id}};
	return;
} # end sub undelete

sub destroy {
	my ( $self ) = @_;
	my $type = ref $self;
	my $table = eval '$'.$type.'::table';
	my $fields = eval '\%'.$type.'::fields';
	my @identified_by = eval '@'.$type.'::identified_by';
	@identified_by = ( 'id' ) if ! @identified_by;
	if ( ! $$self{$identified_by[0]} ) {
		$log->error("Called delete on object with no id of type $type : " . $self->to_string());
		return "Object::delete: No id in object: " . $self->to_string();
	} # end if
	my $local_dbh = eval '$'.$type.'::dbh';
	$local_dbh = $openprint::dbh if ! $local_dbh;
	my $where = join(' AND ', map { $$fields{$_}.'=?' } @identified_by );
	sql::execute( undef, $local_dbh, 'DELETE FROM '.$table.' WHERE '.$where, @$self{@identified_by} );
	return $local_dbh->errstr if $local_dbh->errstr;
  (new openprint::Log())->save({action=>'Destroy', note=>$self->to_string()}) if $type ne 'openprint::Log';
	delete $openprint::Object::cache{$type}{join('-',@$self{@identified_by})};
	eval 'if ( %'.$type.'::find_cache ) { %'.$type.'::find_cache = (); }';
	return '';
} # end sub destroy

sub Creator {
	require openprint::User;
	return new openprint::User( $_[0]{created_by} );
} # end sub Creator

my @sql_functions = (
	'NOW()','CURRENT_TIME',
);

# We make this a separate function so that we can use it to generate the sql statements for each value in an OR
sub find_operators {
	my ( $field, $type, $operator, $value ) = @_;
$log->debug("find_operators: field($field) type($type) op($operator) value($value)") if DEBUG_ALL;

my $add_placeholder = ( ! ( $field =~ /\?/ ) ) ?  1 : 0;

	if ( sets::isin( $operator, [ '=', '!=', '<', '>', '<=', '>=', '<<=', '>>=', '<<', '>>' ] ) ) {
		return ( $field.$type.' ' . $operator . ( $add_placeholder ? ' ?' : '' ), $value );
	} elsif ( $operator eq 'not' ) {
		return ( '( NOT ' . $field.$type.')', $value );
	} elsif ( sets::isin( $operator, [ '&&', '<@', '@>' ] ) ) {
		if ( ref $value eq 'ARRAY' ) {
			if ( $field =~ /^\(/ ) {
				return ( 'ARRAY('.$field.$type.') ' . $operator . ' ?', $value );
			} else {
				return ( $field.$type.' ' . $operator . ' ?', $value );
			} # emd of
		} else {
			return ( $field.$type.' ' . $operator . ' ?', [ $value ] );
		} # end if
	} elsif ( $operator eq 'exists' ) {
			return ( $value ? '' : 'NOT ' ) . 'EXISTS ' . $field.$type;
	} elsif ( sets::isin( $operator, [ 'in', 'not in' ] ) ) {
		if ( ref $value eq 'ARRAY' ) {
			return ( $field.$type.' ' . $operator . ' ('. join(',', map { '?' } @{$value} ) . ')', @{$value} );
		} elsif ( ref $value eq 'HASH' ) {
			return ( $field.$type.' ' . $operator . ' ('.$$value{sql}.')', @{$$value{values}} );
		} else {
			return ( $field.$type.' ' . $operator . ' (?)', $value );
		} # end if
	} elsif ( $operator eq 'contains' ) {
		return ( '? IN '.$field.$type, $value );
	} elsif ( $operator eq 'does not contain' ) {
		return ( '? NOT IN '.$field.$type, $value );
	} elsif ( sets::isin( $operator, [ 'like','ilike' ] ) ) {
		return $field.'::text ' . $operator . ' ?', $value;
	} elsif ( $operator eq 'null_or_<=' ) {
		return '('.$field.$type.' IS NULL OR '.$field.$type.' <= ?)', $value;
	} elsif ( $operator eq 'is null or <=' ) {
		return '('.$field.$type.' IS NULL OR '.$field.$type.' <= ?)', $value;
	} elsif ( $operator eq 'null_or_>=' ) {
		return '('.$field.$type.' IS NULL OR '.$field.$type.' >= ?)', $value;
	} elsif ( $operator eq 'is null or >=' ) {
		return '('.$field.$type.' IS NULL OR '.$field.$type.' >= ?)', $value;
	} elsif ( $operator eq 'null_or_>' or $operator eq 'is null or >' ) {
		return '('.$field.$type.' IS NULL OR '.$field.$type.' > ?)', $value;
	} elsif ( $operator eq 'null_or_<' or $operator eq 'is null or <' ) {
		return '('.$field.$type.' IS NULL OR '.$field.$type.' < ?)', $value;
	} elsif ( $operator eq 'null_or_=' or $operator eq 'is null or =' ) {
		return '('.$field.$type.' IS NULL OR '.$field.$type.' = ?)', $value;
	} elsif ( $operator eq 'is null or !=' ) {
		return '('.$field.$type.' IS NULL OR '.$field.$type.' != ?)', $value;
	} elsif ( $operator eq 'null or in' or $operator eq 'is null or in' ) {
		return '('.$field.$type.' IS NULL OR '.$field.$type.' IN ('.join(',', map { '?' } @{$value} ) . '))', @{$value};
	} elsif ( $operator eq 'null or not in' ) {
		return '('.$field.$type.' IS NULL OR '.$field.$type.' NOT IN ('.join(',', map { '?' } @{$value} ) . '))', @{$value};
	} elsif ( $operator eq 'lc' ) {
		return 'lower('.$field.$type.') = ?', $value;
	} elsif ( $operator eq 'uc' ) {
		return 'upper('.$field.$type.') = ?', $value;
	} elsif ( $operator eq 'trunc' ) {
		return 'trunc('.$field.$type.') = ?', $value;
	} elsif ( $operator eq 'any' ) {
		if ( ref $value eq 'ARRAY' ) {
			return '(' . join(',', map { '?' } @{$value} ).") = ANY($field)", @{$value};
		} else {
			return "? = ANY($field)", $value;
		} # end if
	} elsif ( $operator eq 'not any' ) {
		if ( ref $value eq 'ARRAY' ) {
			return '(' . join(',', map { '?' } @{$value} ).") != ANY($field)", @{$value};
		} else {
			return "? != ANY($field)", $value;
		} # end if
	} elsif ( $operator eq 'is null' ) {
		if ( $value ) {
			return $field.$type. ' is null';
		} else {
			return $field.$type. ' is not null';
		} # end if
	} elsif ( $operator eq 'is not null' ) {
		if ( $value ) {
			return $field.$type. ' is not null';
		} else {
			return $field.$type. ' is null';
		} # end if
	} else {
$log->warn("find_operators: op not found field($field) type($type) op($operator) value($value)");
	} # end if
	return;
} # end sub find_operators

sub get_fields_values {
	my ( $object_type, $search, $param_keys ) = @_;

	my @used_fields;
	my @where;
	my @values;
	no strict 'refs';

	foreach my $k ( @$param_keys ) {
		if ( $k eq 'or' ) {
			my $or_ref = ref $$search{or};

			if ( $or_ref eq 'HASH' ) {
				my @keys = keys %{$$search{or}};
				if ( @keys ) {
					my ( $where, $values, $used_fields ) = get_fields_values( $object_type, $$search{or},  \@keys );

					push @where, '('.join(' OR ', @{$where} ).')';
					push @values, @{$values};
				} else {
					$log->error("No keys in or");
				}

			} elsif ( $or_ref eq 'ARRAY' ) {
				my %s = @{$$search{or}};
				my ( $where, $values, $used_fields ) = get_fields_values( $object_type, \%s,  [ keys %s ] );
				push @where, '('.join(' OR ', @{$where} ).')';
				push @values, @{$values};

			} else {
				$log->error("Deprecated use of or $or_ref for $$search{or}");
			} # end if
			push @used_fields, $k;
			next;
		} elsif ( $k eq 'and' ) {
			my $and_ref = ref $$search{and};
			if ( $and_ref eq 'HASH' ) {
				my @keys = keys %{$$search{and}};
				if ( @keys ) {
          my ( $where, $values, $used_fields ) = get_fields_values( $object_type, $$search{and},  \@keys );

          push @where, '('.join(' AND ', @{$where} ).')';
          push @values, @{$values};
				} else {
					$log->error("No keys in and");
				}
			} elsif ( $and_ref eq 'ARRAY' and @{$$search{and}} ) {
				my @sub_where;

				for( my $p_index = 0; $p_index < @{$$search{and}}; $p_index += 2 ) {
					my %p = ( $$search{and}[$p_index], $$search{and}[$p_index+1] );

					my ( $where, $values, $used_fields ) = get_fields_values( $object_type, \%p, [ keys %p ] );
					push @sub_where, @{$where};
					push @values, @{$values};
				}
				push @where, '('.join(' AND ', @sub_where ).')';
			} else {
				$openprint::log->error("incorrect ref of and $and_ref");
			}
			push @used_fields, $k;
			next;
		}
		my ( $field, $type, $function ) = $k =~ /^([_\+\w\-]+)(::\w+\[?\]?)?[\s_]*(.*)?$/;
		$type = '' if ! defined $type;
    $function = '' if ! defined $function;
    #$log->debug("$object_type param $field($type) func($function) " . ( ref $$search{$k} eq 'ARRAY' ? join(',',@{$$search{$k}}) : $$search{$k} ) ) if DEBUG_ALL;

		foreach ( 'find_fields', 'fields' ) {
			my $fields = \%{$object_type.'::'.$_};
			if ( ! $fields ) {
				$log->debug("No $fields in $object_type") if DEBUG_ALL;
				next;
			} # end if

			if ( ! $$fields{$field} ) {
				#$log->debug("No $field in $_ for $object_type") if DEBUG_ALL;
				next;
			} # end if

# This allows mainly for find_fields to reference multiple values, opinion in Project, value
			foreach my $db_field ( ref $$fields{$field} eq 'ARRAY' ? @{$$fields{$field}} : $$fields{$field} ) {
				if ( ! $function ) {
					$db_field .= $type;

					if ( ref $$search{$k} eq 'ARRAY' ) {
$openprint::log->debug("Have array for $k $$search{$k}") if DEBUG_ALL;

						if ( ! ( $db_field =~ /\?/ ) ) {
							if ( @{$$search{$k}} != 1 ) {
								push @where, $db_field .' IN ('.join(',', map {'?'} @{$$search{$k}} ) . ')';
							} else {
								push @where, $db_field.'=?';
							} # end if
						} else {
$openprint::log->debug("Have question ? for $k $$search{$k} $db_field") if DEBUG_ALL;

							$db_field =~ s/=/IN/g;
							my $question_replacement = '('.join(',', map {'?'} @{$$search{$k}} ) . ')';
							$db_field =~ s/\?/$question_replacement/;
							push @where, $db_field;
						}
						push @values, @{$$search{$k}};
					} elsif ( ref $$search{$k} eq 'HASH' ) {
						foreach my $p_k ( keys %{$$search{$k}} ) {
							my $v = $$search{$k}{$p_k};
							if ( ref $v eq 'ARRAY' ) {
								push @where, $db_field.' IN ('.join(',', map {'?'} @{$v} ) . ')';
								push @values, $p_k, @{$v};
							} else {
								push @where, $db_field.'=?';
								push @values, $p_k, $v;
							} # end if
						} # end foreach p_k
					} elsif ( ! defined $$search{$k} ) {
						push @where, $db_field.' IS NULL';
					} else {
						if ( ! ( $db_field =~ /\?/ ) ) {
							push @where, $db_field .'=?';
						} else {
							push @where, $db_field;
						}
						push @values, $$search{$k};
					} # end if
					push @used_fields, $k;
				} else {
					#my @w =
#ref $search{$k} eq 'ARRAY' ?
						#map { find_operators( $field, $type, $function, $_ ); } @{$search{$k}} :
					my ( $w, @v ) = find_operators( $db_field, $type, $function, $$search{$k} );
					if ( $w ) {
						#push @where, '(' . join(' OR ', @w ) . ')';
						push @where, $w;
						push @values, @v if @v;
						push @used_fields, $k;
					} # end if @w
				} # end if has function or not
			} # end foreach db_field
		} # end foreach find_field
	} # end foreach k
	return ( \@where, \@values, \@used_fields );
}

sub find_sql {
	no strict 'refs';
	my $object_type = shift;

	my $debug = ${$object_type.'::debug'};
	$debug = DEBUG_ALL if ! $debug;

	my $params;
	if ( @_ == 1 ) {
		$params = $_[0];
		if ( ref $params ne 'HASH' ) {
			$log->error("params $params was not a has");
		} # end if
	} else {
		$params = { @_ };
	} # end if

	my %sql = (
		( distinct => ( exists $$params{distinct} ? 1 : 0 ) ),
		( columns => ( exists $$params{columns} ? $$params{columns} : '*' ) ),
		( table => ( exists $$params{table} ? $$params{table} : ${$object_type.'::table'} )),
		'group by'=> $$params{'group by'},
		limit => $$params{limit},
		offset => $$params{offset},
	);
	if ( exists $$params{order} ) {
		$sql{order} = $$params{order};
	} else {
		my $order = eval '$'.$object_type.'::default_sort';
#$log->debug("default sort: $object_type :: default_sort = $order") if DEBUG_ALL;
		$sql{order} = $order if $order;
	} # end if
	delete @$params{'distinct','columns','table','group by','limit','offset','order'};

	my @where;
	my @values;
	if ( exists $$params{custom} ) {
		push @where, '(' . (shift @{$$params{custom}}) . ')';
		push @values, @{$$params{custom}};
		delete $$params{custom};
	} # end if

	my @param_keys = keys %$params;

	# no operators, just which fields are being searched on. Mostly just useful for detetion of the deleted field.
	my %used_fields;

	# We use this search hash so that we can mash it up and leave the params hash alone
	my %search;
	@search{@param_keys} = @$params{@param_keys};

	my ( $where, $values, $used_fields ) = get_fields_values( $object_type, \%search, \@param_keys );
	delete @search{@{$used_fields}};
	@used_fields{ @{$used_fields} } = @{$used_fields};
	push @where, @{$where};
	push @values, @{$values};

	my $fields = \%{$object_type.'::fields'};
# Check for Object references
	if ( 0 and  %search ) {
$openprint::log->debug("Using search");
		foreach my $k ( keys %search ) {
			if ( sets::isin( ref $search{$k}, [ '', 'SCALAR','ARRAY','HASH' ] ) ) {
$openprint::log->error("Wasting time looking for objects in find $k $search{$k}");
				next;
			}
			my $f = (lc $k).'_id';
			if ( exists $$fields{$f} ) {
				Carp::cluck("Use of deprecated Object ref in find");
				if ( $search{$k}->id() ) {
					push @where, $$fields{$f}.' = ?';
					push @values, $search{$k}->id();
				} else {
					push @where, "$$fields{$f} IS NULL";
				} # end if
				delete $search{$k};
			} # end if
		} # end foreach
	} # end if

#optimise this
	if ( $$fields{deleted} and ! $used_fields{deleted} ) {
		push @where, 'deleted=?';
		push @values, 0;
	} # end if
	$sql{where} = \@where;
	$sql{values} = \@values;
	$sql{used_fields} = \%used_fields;

	foreach my $k ( keys %search ) {
		$log->error("Extra parameters in $object_type ::find $k => $search{$k}");
		Carp::cluck("Extra parameters in $object_type ::find $k => $search{$k}");
	} # end foreach

	$sql{sql} = join( ' ',
			( 'SELECT', ( $sql{distinct} ? ('DISTINCT') : () ) ),
			( $sql{columns}, 'FROM', $sql{table} ),
			( @{$sql{where}} ? ('WHERE', join(' AND ', @{$sql{where}})) : () ),
			( $sql{order} ? ( 'ORDER BY', $sql{order} ) : () ),
			( $sql{'group by'} ? ( 'GROUP BY', $sql{'group by'} ) : () ),
			( $sql{limit} ? ( 'LIMIT', $sql{limit}) : () ),
			( $sql{offset} ? ( 'OFFSET', $sql{offset} ) : () ),
	);
	$log->debug("find_sql $object_type ($sql{sql}) (".join(',', map { ref $_ eq 'ARRAY' ? join(',', @{$_}) : $_ } @values).')' ) if $debug;
	return \%sql;
} # end sub find_sql

sub find {
	no strict 'refs';
	my $object_type = shift;
	my $debug = ${$object_type.'::debug'};
	$debug = DEBUG_ALL if ! $debug;

	my $starttime = [gettimeofday] if $debug;
	my $params;
	if ( @_ == 1 ) {
		$params = $_[0];
		if ( ref $params ne 'HASH' ) {
			$log->error("params $params was not a has");
		} # end if
	} else {
		$params = { @_ };
	} # end if

	my $local_dbh = ${$object_type.'::dbh'};
	if ( $$params{dbh} ) {
		$local_dbh = $$params{dbh};
		delete $$params{dbh};
	} elsif ( ! $local_dbh ) {
    #$local_dbh = $object_type->connect();
		$local_dbh = $openprint::dbh if ! $local_dbh;
	} # end if

	my $sql = find_sql($object_type, $params);

	my $do_cache = (index($$sql{columns}, '*') != -1) ? 0 : 1;
	my $cache_field = ${$object_type.'::cache_field'} if $do_cache;
	if ( ( 1 == scalar keys %{$$sql{used_fields}} ) and $$params{id} ) {
		if ( $cache{$object_type}{$$params{id}} ) {
			if ( $cache{$object_type}{$$params{id}}{id} ) {
				my ( $caller, undef, $line ) = caller;
				$log->debug('returning ' . $name_cache{$object_type}{$$params{$cache_field}} . " to $caller:$line for $object_type $cache_field $$params{$cache_field}") if DEBUG_ALL;
				return ( $cache{$object_type}{$$params{id}} );
			} else {
				my ( $caller, undef, $line ) = caller;
				$log->debug('Not returning ' . $name_cache{$object_type}{$$params{$cache_field}} . " to $caller:$line for $object_type $cache_field $$params{$cache_field}") if DEBUG_ALL;
			}
		}
	} elsif ( $cache_field and $$params{$cache_field} and ( 1 == (scalar keys %{$$sql{used_fields}}) ) ) {

		$log->debug("have cache field $cache_field for $$params{$cache_field}") if DEBUG_ALL;
		if ( exists $name_cache{$object_type} and exists $name_cache{$object_type}{$$params{$cache_field}} ) {
			$log->debug("There is an object in the cache for $$params{$cache_field}") if DEBUG_ALL;
			if ( $name_cache{$object_type}{$$params{$cache_field}} ) {
				my ( $caller, undef, $line ) = caller;
				$log->debug("returning " . $name_cache{$object_type}{$$params{$cache_field}} . " to $caller:$line for $object_type $cache_field $$params{$cache_field}") if DEBUG_ALL;
				return ( $name_cache{$object_type}{$$params{$cache_field}} );
			} else {
				# Shouldn't have to test for cached, because the hash will not get populated.
$log->debug("returning nothing for $object_type $cache_field $$params{$cache_field}") if DEBUG_ALL;
				return ();
			} # end if
		} else { # not in cache
			my $cached = eval('$'.$object_type.'::cached');
			if ( $cached ) {
				# if all items should have been loaded

# Can only undef here if we know that we have already loaded them all
				$log->debug("Undefing $object_type cached: $cached $cache_field $$params{$cache_field} cache: so that future lookups find an empty cache") if DEBUG_ALL or DEBUG_CACHE;
	#debug();
				$name_cache{$object_type}{$$params{$cache_field}} = undef;
	#$log->debug("ALl cached $object_type $cache_field $$params{$cache_field}") if DEBUG_ALL or DEBUG_CACHE;
				return ();
			} # end if Object::cached
		} # end if is in cache or not
	} else {
		$do_cache = 0;
		$log->debug("Not doing caching for $object_type using $cache_field with params ".($cache_field?$$params{$cache_field}:'')) if DEBUG_ALL or DEBUG_CACHE;
	} # end if

#$log->debug( 'find prepare: ' . sprintf('%.4f', tv_interval($starttime)*1000) ." useconds") if $debug;
	my $data = $local_dbh->selectall_arrayref($$sql{sql}, { Slice => {} }, @{$$sql{values}});
	if ( ! $data ) {
		$log->error('Error ' . $local_dbh->errstr() . " loading $object_type ($$sql{sql}) (". join(',', map { ref $_ eq 'ARRAY' ? 'ARRAY('.join(',',@$_).')' : $_ } @{$$sql{values}} ) . ')' );
		return ();
	#} elsif ( ( ! @$data ) and $debug ) {
		#$log->debug("No $type ($sql) (@values) " );
	} elsif ( $debug ) {
		$log->debug("Loading Debug:$debug $object_type ($$sql{sql}) (".join(',', map { ref $_ eq 'ARRAY' ? join(',', @{$_}) : $_ } @{$$sql{values}}).') # of results:' . @$data . ' in ' . sprintf('%.4f', tv_interval($starttime)*1000) .' useconds' );
	} # end if
  return () if !@{$data};

	my $fields = \%{$object_type.'::fields'};
	if ( $$fields{id} ) {
		if ( $cache_field ) {
			my @results = map { $object_type->new( $_->{$$fields{id}}, $_ ) } @$data;
			$name_cache{$object_type} = {} if ! $name_cache{$object_type};
			my $cache_ref = $name_cache{$object_type};
$log->debug("Doing find_cache for $object_type $cache_ref $name_cache{$object_type}") if DEBUG_ALL;

			foreach my $O ( @results ) {
				next if !$$O{$cache_field};
				$cache_ref->{$$O{$cache_field}} = $O;
#$log->warn("Doing find_cache for $object_type $$O{$cache_field}");
			}
#debug();
			return @results;
		} # end if
		return map { new($object_type, $_->{$$fields{id}}, $_) } @{$data};
	} else {
		my @identified_by = eval '@'.$object_type.'::identified_by';
		if ( ! @identified_by ) {
			$log->debug("Multi key object $object_type but no identified by") if $debug;
		} # end if
		return map { new($object_type, \@identified_by, $_, !$do_cache) } @$data;
	} # end if
} # end sub find

sub find_one {
	my $object_type = shift;
	my $params;
	if ( @_ == 1 ) {
		$params = $_[0];
	} else {
		%{$params} = @_;
	} # end if
	if ( ((scalar keys %{$params}) == 1) and $$params{id} ) {
		my $id = $$params{id};
		$cache{$object_type} = {} if ! $cache{$object_type};
		my $sub_cache = $cache{$object_type};
    return $$sub_cache{$id} if $$sub_cache{$id};
	}
	$$params{limit} = 1;
	my @Results = $object_type->find(%$params);
	my ( $caller, undef, $line ) = caller;
$log->debug("returning $Results[0] to $caller:$line from $object_type find_one") if DEBUG_ALL;
	return $Results[0] if @Results;
} # end sub find_one

sub AUTOLOAD {
	no strict;
	my ( $self, $newvalue ) = @_;
	my $type = ref($self);
	if ( ! $type ) {
		my ( $caller, undef, $line ) = caller;
		$log->error("No type in Object::AUTOLOAD. self:$self from  $caller:$line");
	}
	my $name = $AUTOLOAD;
	$name =~ s/.*://;
	my $fields = eval '\%'.$type.'::fields';
	if ( @_ > 1 ) {
		if ( $fields ) {
			# This looks to handle returning Objects
			if ( ! exists $$fields{$name} ) {
				Carp::cluck( "Bad autoload $type $name  = $_[1]" );
			} # end if
		} # end if
$openprint::log->debug("Autoload $type $name $_[0] $_[1] $self $newvalue") if ! $type;
*{$name} = sub {
      @_ > 1 ? $_[0]->{$name} = $_[1]
        : $_[0]->{$name};
    };
		return $_[0]{$name} = $_[1];
	} else {
		if ( $fields ) {
			# This looks to handle returning Objects
			if ( exists $$fields{$name} ) {

# NOT SURE WE SHOULD DO THIS
				#if ( ! defined $_[0]{$name} ) {
					#my $defaults = eval '\%'.$type.'::defaults';
					#if ( exists $$defaults{$name} ) {
						#return $$defaults{$name};
					#}
				#} # end if
        # This creates a function entry in the object so that we don't call AUTOLOAD
        # Instead of creating a new anonymous sub... shouldn't we point it at an existing sub?
        *{$name} = sub {
          @_ > 1 ? $_[0]->{$name} = $_[1] : $_[0]->{$name};
        };
				return $_[0]{$name};
			} else {
				my $field = (lc $name) . '_id';
				if ( exists $$fields{$field} ) {
					my $O = eval {
						require "openprint/$name.pm";
						return ('openprint::'.$name)->new( $_[0]{$field} );
					}; # end eval
					if ( $@ ){
						$log->error( "Eval error of Object::AUTOLOAD $type -> $name, Reason: " . $@ );
						return;
					} # end if
					return $O;
				} # end if
			} # end if
		} # end if has fields
	} # end if setting
	Carp::cluck( "Bad autoload $type $name " );
	return;
} # end sub AUTOLOAD

sub to_string {
	my $type = ref($_[0]);
	my $fields = eval '\%'.$type.'::fields';
	return $type . ': '. join(' ', map {
#$$fields{$_} ? $_ . ' => ' . (ref $_[0]{$_} eq 'ARRAY' ? join(',',@{$_[0]{$_}}) : $_[0]{$_} )
 $_ . ' => ' . (ref $_[0]{$_} eq 'ARRAY' ? join(',',@{$_[0]{$_}}) : (defined( $_[0]{$_})?$_[0]{$_}:'undef') )
#: ()
} sort { $a cmp $b } keys %$fields );
}

sub dropdown {
	my $self = shift;
	my %params = @_;

  my $type = ref($self);
  $type = $self if ! $type;
	if ( ! $params{order} ) {
		my $order = eval '$'.$type.'::default_sort';
#$log->debug("default sort: $self $type :: default_sort = $order") if DEBUG_ALL;
		$params{order} = $order if $order;
	}
  my $field = eval '$'.$type.'::dropdown_field';
  $field = 'name' if ! $field;

	# User has firstname,lastname
	#if ( ( ! $params{columns} ) {
		#$params{columns} = 'id,name';
	#}

	return [ map { $$_{id}, ssi::html_escape($_->$field()) } $self->find(%params) ];
} # end sub dropdown

sub sort_value {
	return $_[0]->name();
}

sub sort {
	my $type = shift;
	my @results = sort { $$a{name} cmp $$b{name} } @_;
	return @results;
} # end sub sort

# Warning, this is destructive to objects
sub transform {
	my $type = ref $_[0];
	$type = $_[0] if ! $type;
	my $fields = eval '\%'.$type.'::fields';
	my $value = $_[2];

	if (defined $$fields{$_[1]}) {
		my @transforms = eval('$'.$type.'::transforms{$_[1]} ? @{$'.$type.'::transforms{$_[1]}} : ()');
		$openprint::log->debug("Transforms for $_[1] before $_[2]: @transforms") if $debug;
		if ( @transforms ) {
			foreach my $transform ( @transforms ) {
				if ( $transform =~ /^s\// or $transform =~ /^tr\// ) {
					eval '$value =~ '.$transform;
				} elsif ( $transform =~ /^<(\d+)/ ) {
					if ( $value > $1 ) {
						$value = undef;
					} # end if
				} else {
	$openprint::log->debug("evalling $value ".$transform . " Now value is $value" );
					eval '$value '.$transform;
	$openprint::log->error("Eval error $@") if $@;
				}
	$openprint::log->debug("After $transform: $value") if $debug;
			} # end foreach
		} # end if
	} else {
		$openprint::log->error("Object::transform ($_[1]) not in fields for $type");
	} # end if
	return $value;

} # end sub transform

sub Object_Type {
	if ( $_[0]{object_type_id} ) {
		$_[0]{Object_Type} = new openprint::Object_Type( $_[0]{object_type_id} );
	} else {
		$_[0]{Object_Type} = openprint::Object_Type->find_one( name=>ref $_[0] );
		$_[0]{Object_Type} = new openprint::Object_Type() if ! $_[0]{Object_Type};
	} # end if
	return $_[0]{Object_Type};
} # end sub Object_Type

sub object_type {
	if ( @_ > 1 ) {
		my $Type = openprint::Object_Type->find_one( name => $_[1] );
		if ( ! $Type ) {
			$Type = new openprint::Object_Type();
			$Type->save({ name=>$_[1], human=>$_[1] });
		} # end if
		$_[0]{object_type} = $Type->name();
		$_[0]{object_type_id} = $Type->id();
	} # end if
	if ( ! $_[0]{object_type} ) {
		$_[0]{object_type} = new openprint::Object_Type( $_[0]{object_type_id} )->name();
	} # end if
	return $_[0]{object_type};
} # end sub object_type

sub Object {
  my $self = shift;
	if ( @_ ) {
		$self->object_type( ref $_[0] );
		$$self{object_id} = $_[0]{id};
    $$self{Object} = $_[0];
	} # end if
	my $type =  $self->object_type();
	if ( !$type ) {
		$log->error('No type in Object::Object'. $self->to_string()) if ref $self ne 'openprint::Log';
		return undef;
	} # end if
	my ( $module ) = $type =~ /openprint::(.*)/;
	if ( $module ) {
		eval {
			require "openprint/$module.pm";
		};
    if ( ! $$self{Object} ) {
      $_ = $type->new($$self{object_id});
      $openprint::log->debug( 'Returning object of type ' . ref $_ ) if $debug;
      $$self{Object} = $_;
    }
		return $$self{Object};
	} else {
		$log->error("Unvalid object $type");
		return new openprint::Object();
	}
} # end sub Object

sub can_view {
	return 1;
} # end sub can_view

sub can_edit {
	if ( $openprint::session{user_type} eq 'A' ) {
    return 1;
	}
	return 0;
} # end sub can_edit

sub DESTROY {
}

sub lock {
	my ( $caller, undef, $line ) = caller;

	my $type = ref $_[0];
	my $ac;
	if ( $type ) {
		# Row lock
		if ( $_[0]{ac} ) {
			#already locked, actually a zero value could mean that a transaction was already in progress, just not on this object.
			$openprint::log->debug("ALREADY LOCKED $type for $_[0]{id} ac: $_[0]{ac} caller: $caller line: $line object ref:" . $_[0]) if DEBUG_LOCKS;
			$_[0]{ac} += 1;
		} else {
			# Should return 1, which was the previous state of the AutoCommit which is now 0
			# Could return 0 if we were already in a transaction
			# If we were already in a stransaction, then when we go to unlock... it won't actually unlock...
			$_[0]{ac} = sql::start_transaction( $openprint::dbh );
			$openprint::log->debug("LOCKING $type for $_[0]{id} ac: $_[0]{ac} caller: $caller line: $line object ref:" . $_[0]) if DEBUG_LOCKS;
			my $table = eval '$'.$type.'::table';
			$dbh->do( "SELECT * FROM $table WHERE id=".$_[0]{id}. ' FOR UPDATE' ) or $log->error( $dbh->errstr );
			#$dbh->do( "LOCK TABLE $table IN EXCLUSIVE MODE" ) or $log->error( DBI->errstr );
		} # end if
		$ac = $_[0]{ac};
	} else {
		$type = $_[0];
		# Table Lock
		my $ac = sql::start_transaction( $openprint::dbh );
		$openprint::log->debug("LOCKING $type table ac: caller: $caller line: $line" ) if DEBUG_LOCKS;
		my $table = eval '$'.$type.'::table';
		$dbh->do( "LOCK TABLE $table IN EXCLUSIVE MODE" ) or $log->error( DBI->errstr );
	} # end  if
	return $ac;

} # end sub lock

sub unlock {
	my ( $caller, undef, $line ) = caller;
	my $type = ref $_[0];
	if ( $type ) {
		$openprint::log->debug("UNLOCKING $type for $_[0]{id} ac: $_[0]{ac} caller: $caller line: $line" . $_[0]) if DEBUG_LOCKS;
		if ( ! exists $_[0]{ac} ) {
			# THis doesn't work.  If we were in a transaction, then AutoCommit is 0
$openprint::log->debug("UNLOCKING $type for $_[0]{id} ac: $_[0]{ac} caller: $caller line: $line" . $_[0] . ' does not exist ac' );
			$_[0]{ac} = $openprint::dbh->{AutoCommit};
		} # end if
		if ( ! $_[0]{ac} ) {
			$openprint::log->debug("unlock with no AC! $caller:$line object $type $_[0]{id}");
			return;
		} # end if
		if ( $_[0]{ac} == 1 ) {
			sql::end_transaction( $openprint::dbh, $_[0]{ac} );
		} # end if
		$_[0]{ac} -= 1;
	} else {
		$type = $_[0];
		$openprint::log->debug("UNLOCKING $type ac: caller: $caller line: $line" ) if DEBUG_LOCKS;
		sql::end_transaction( $openprint::dbh, 1 );
	}
} # end sub unlock

sub TO_JSON {
  my $self = shift;
  my $type = ref $self;
  my $fields = eval('\%'.$type.'::fields');

  # copy all the sql backed fields, as there might be other things in the object.
  my %simple_hash;
  my @keys = map { defined $$fields{$_} ? $_ : () } keys %$fields;
  @simple_hash{@$fields{@keys}} = @$self{@keys};
  return \%simple_hash;
}

1;
__END__
