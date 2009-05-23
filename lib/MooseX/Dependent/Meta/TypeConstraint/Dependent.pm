package ## Hide from PAUSE
 MooseX::Dependent::Meta::TypeConstraint::Dependent;

use Moose;
use Moose::Util::TypeConstraints ();
use MooseX::Dependent::Meta::TypeCoercion::Dependent;
use Scalar::Util qw(blessed);
use Data::Dump;
use Digest::MD5;
            
extends 'Moose::Meta::TypeConstraint';

=head1 NAME

MooseX::Dependent::Meta::TypeConstraint::Dependent - Metaclass for Dependent type constraints.

=head1 DESCRIPTION

see L<MooseX::Dependent> for examples and details of how to use dependent
types.  This class is a subclass of L<Moose::Meta::TypeConstraint> which
provides the gut functionality to enable dependent type constraints.

=head1 ATTRIBUTES

This class defines the following attributes.

=head2 parent_type_constraint

The type constraint whose validity is being made dependent.

=cut

has 'parent_type_constraint' => (
    is=>'ro',
    isa=>'Object',
    default=> sub {
        Moose::Util::TypeConstraints::find_type_constraint("Any");
    },
    required=>1,
);


=head2 constraining_value_type_constraint

This is a type constraint which defines what kind of value is allowed to be the
constraining value of the dependent type.

=cut

has 'constraining_value_type_constraint' => (
    is=>'ro',
    isa=>'Object',
    default=> sub {
        Moose::Util::TypeConstraints::find_type_constraint("Any");
    },
    required=>1,
);

=head2 constraining_value

This is the actual value that constraints the L</parent_type_constraint>

=cut

has 'constraining_value' => (
    is=>'ro',
    predicate=>'has_constraining_value',
);

=head1 METHODS

This class defines the following methods.

=head2 BUILD

Do some post build stuff

=cut

## Right now I add in the dependent type coercion until I can merge some Moose
## changes upstream

around 'new' => sub {
    my ($new, $class, @args) = @_;
    my $self = $class->$new(@args);
    my $coercion = MooseX::Dependent::Meta::TypeCoercion::Dependent->new(type_constraint => $self);
    $self->coercion($coercion);    
    return $self;
};

=head2 parameterize (@args)

Given a ref of type constraints, create a structured type.
    
=cut

sub parameterize {
    my $self = shift @_;
    my $class = ref $self;

    Moose->throw_error("$self already has a constraining value.") if
     $self->has_constraining_value;
         
    if(blessed $_[0] && $_[0]->isa('Moose::Meta::TypeConstraint')) {
        my $arg1 = shift @_;
         
        if(blessed $_[0] && $_[0]->isa('Moose::Meta::TypeConstraint')) {
            my $arg2 = shift @_ || $self->constraining_value_type_constraint;
            
            ## TODO fix this crap!
            Moose->throw_error("$arg2 is not a type constraint")
             unless $arg2->isa('Moose::Meta::TypeConstraint');
             
            Moose->throw_error("$arg1 is not a type of: ".$self->parent_type_constraint->name)
             unless $arg1->is_a_type_of($self->parent_type_constraint);

            Moose->throw_error("$arg2 is not a type of: ".$self->constraining_value_type_constraint->name)
             unless $arg2->is_a_type_of($self->constraining_value_type_constraint);
             
            Moose->throw_error('Too Many Args!  Two are allowed.') if @_;
            
            my $name = $self->_generate_subtype_name($arg1, $arg2);
            if(my $exists = Moose::Util::TypeConstraints::find_type_constraint($name)) {
                return $exists;
            } else {
                my $type_constraint = $class->new(
                    name => $name,
                    parent => $self,
                    constraint => $self->constraint,
                    parent_type_constraint=>$arg1,
                    constraining_value_type_constraint => $arg2,
                );
                Moose::Util::TypeConstraints::get_type_constraint_registry->add_type_constraint($type_constraint);
                return $type_constraint;
            }
        } else {
            Moose->throw_error("$arg1 is not a type of: ".$self->constraining_value_type_constraint->name)
             unless $arg1->is_a_type_of($self->constraining_value_type_constraint);
             
            my $name = $self->_generate_subtype_name($self->parent_type_constraint, $arg1);
            if(my $exists = Moose::Util::TypeConstraints::find_type_constraint($name)) {
                return $exists;
            } else {
                my $type_constraint = $class->new(
                    name => $name,
                    parent => $self,
                    constraint => $self->constraint,
                    parent_type_constraint=>$self->parent_type_constraint,
                    constraining_value_type_constraint => $arg1,
                );
                Moose::Util::TypeConstraints::get_type_constraint_registry->add_type_constraint($type_constraint);
                return $type_constraint;
            }
        }
    } else {
        my $args;
        ## Jump through some hoops to let them do tc[key=>10] and tc[{key=>10}]
        if(@_) {
            if($#_) {
                if($self->constraining_value_type_constraint->is_a_type_of('HashRef')) {
                    $args = {@_};
                } else {
                    $args = [@_];
                }                
            } else {
                $args = $_[0];
            }

        } else {
            ## TODO:  Is there a use case for parameterizing null or undef?
            Moose->throw_error('Cannot Parameterize null values.');
        }
        
        if(my $err = $self->constraining_value_type_constraint->validate($args)) {
            Moose->throw_error($err);
        } else {

            my $sig = $args;
            if(ref $sig) {
                $sig = Digest::MD5::md5_hex(Data::Dump::dump($args));               
            }
            my $name = $self->name."[$sig]";
            if(my $exists = Moose::Util::TypeConstraints::find_type_constraint($name)) {
                return $exists;
            } else {
                my $type_constraint = $class->new(
                    name => $name,
                    parent => $self,
                    constraint => $self->constraint,
                    constraining_value => $args,
                    parent_type_constraint=>$self->parent_type_constraint,
                    constraining_value_type_constraint => $self->constraining_value_type_constraint,
                );
                
                ## TODO This is probably going to have to go away (too many things added to the registry)
                ##Moose::Util::TypeConstraints::get_type_constraint_registry->add_type_constraint($type_constraint);
                return $type_constraint;
            }
        }
    } 
}

=head2 _generate_subtype_name

Returns a name for the dependent type that should be unique

=cut

sub _generate_subtype_name {
    my ($self, $parent_tc, $constraining_tc) = @_;
    return sprintf(
        $self."[%s, %s]",
        $parent_tc, $constraining_tc,
    );
}

=head2 create_child_type

modifier to make sure we get the constraint_generator

=cut

around 'create_child_type' => sub {
    my ($create_child_type, $self, %opts) = @_;
    if($self->has_constraining_value) {
        $opts{constraining_value} = $self->constraining_value;
    }
    return $self->$create_child_type(
        %opts,
        parent=> $self,
        parent_type_constraint=>$self->parent_type_constraint,
        constraining_value_type_constraint => $self->constraining_value_type_constraint,
    );
};

=head2 equals ($type_constraint)

Override the base class behavior so that a dependent type equal both the parent
type and the overall dependent container.  This behavior may change if we can
figure out what a dependent type is (multiply inheritance or a role...)

=cut

around 'equals' => sub {
    my ( $equals, $self, $type_or_name ) = @_;
    
    my $other = defined $type_or_name ?
      Moose::Util::TypeConstraints::find_type_constraint($type_or_name) :
      Moose->throw_error("Can't call $self ->equals without a parameter");
      
    Moose->throw_error("$type_or_name is not a registered Type")
     unless $other;
     
    if(my $parent = $other->parent) {
        return $self->$equals($other)
         || $self->parent->equals($parent);        
    } else {
        return $self->$equals($other);
    }
};

=head2 is_subtype_of

Method modifier to make sure we match on subtype for both the dependent type
as well as the type being made dependent

=cut

around 'is_subtype_of' => sub {
    my ( $is_subtype_of, $self, $type_or_name ) = @_;

    my $other = defined $type_or_name ?
      Moose::Util::TypeConstraints::find_type_constraint($type_or_name) :
      Moose->throw_error("Can't call $self ->equals without a parameter");
      
    Moose->throw_error("$type_or_name is not a registered Type")
     unless $other;
     
    return $self->$is_subtype_of($other)
        || $self->parent_type_constraint->is_subtype_of($other);

};

=head2 check

As with 'is_subtype_of', we need to dual dispatch the method request

=cut

around 'check' => sub {
    my ($check, $self, @args) = @_;
    return (
        $self->parent_type_constraint->check(@args) &&
        $self->$check(@args)
    );
};

=head2 validate

As with 'is_subtype_of', we need to dual dispatch the method request

=cut

around 'validate' => sub {
    my ($validate, $self, @args) = @_;
    return (
        $self->parent_type_constraint->validate(@args) ||
        $self->$validate(@args)
    );
};

=head2 _compiled_type_constraint

modify this method so that we pass along the constraining value to the constraint
coderef and also throw the correct error message if the constraining value does
not match it's requirement.

=cut

around '_compiled_type_constraint' => sub {
    my ($method, $self, @args) = @_;
    my $coderef = $self->$method(@args);
    my $constraining;
    if($self->has_constraining_value) {
        $constraining = $self->constraining_value;
    } 
    
    return sub {
        my @local_args = @_;
        if(my $err = $self->constraining_value_type_constraint->validate($constraining)) {
            Moose->throw_error($err);
        }
        $coderef->(@local_args, $constraining);
    };
};

=head2 coerce

More method modification to support dispatch coerce to a parent.

=cut

around 'coerce' => sub {
    my ($coerce, $self, @args) = @_;
    
    if($self->has_constraining_value) {
        push @args, $self->constraining_value;
        if(@{$self->coercion->type_coercion_map}) {
            my $coercion = $self->coercion;
            my $coerced = $self->$coerce(@args);
            if(defined $coerced) {
                return $coerced;
            } else {
                my $parent = $self->parent;
                return $parent->coerce(@args); 
            }
        } else {
            my $parent = $self->parent;
            return $parent->coerce(@args); 
        } 
    }
    else {
        return $self->$coerce(@args);
    }
    return;
};

=head2 get_message

Give you a better peek into what's causing the error.

around 'get_message' => sub {
    my ($get_message, $self, $value) = @_;
    return $self->$get_message($value);
};

=head1 SEE ALSO

The following modules or resources may be of interest.

L<Moose>, L<Moose::Meta::TypeConstraint>

=head1 AUTHOR

John Napiorkowski, C<< <jjnapiork@cpan.org> >>

=head1 COPYRIGHT & LICENSE

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
##__PACKAGE__->meta->make_immutable(inline_constructor => 0);

