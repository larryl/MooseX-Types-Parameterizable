package MooseX::Types::Parameterizable;

use 5.008;

our $VERSION   = '0.02';
$VERSION = eval $VERSION;

use Moose::Util::TypeConstraints;
use MooseX::Meta::TypeConstraint::Parameterizable;
use MooseX::Types -declare => [qw(Parameterizable)];

=head1 NAME

MooseX::Types::Parameterizable - Create your own Parameterizable Types.

=head1 SYNOPSIS

The follow is example usage.

    package Test::MooseX::Types::Parameterizable::Synopsis;

    use Moose;
    use MooseX::Types::Parameterizable qw(Parameterizable);
    use MooseX::Types::Moose qw(Str Int ArrayRef);
    use MooseX::Types -declare=>[qw(Varchar)];

    ## Create a type constraint that is a string but parameterizes an integer
    ## that is used as a maximum length constraint on that string, similar to
    ## a SQL Varchar database type.

    subtype Varchar,
      as Parameterizable[Str,Int],
      where {
        my($string, $int) = @_;
        $int >= length($string) ? 1:0;
      },
      message { "'$_' is too long"  };

    ## Coerce an ArrayRef to a string via concatenation.

    coerce Varchar,
      from ArrayRef,
      via { 
        my ($arrayref, $int) = @_;
        join('', @$arrayref);
      };

    has 'varchar_five' => (isa=>Varchar[5], is=>'ro', coerce=>1);
    has 'varchar_ten' => (isa=>Varchar[10], is=>'ro');
  
    ## Object created since attributes are valid
    my $object1 = __PACKAGE__->new(
        varchar_five => '1234',
        varchar_ten => '123456789',
    );

    ## Dies with an invalid constraint for 'varchar_five'
    my $object2 = __PACKAGE__->new(
        varchar_five => '12345678',  ## too long!
        varchar_ten => '123456789',
    );

    ## varchar_five coerces as expected
    my $object3 = __PACKAGE__->new(
        varchar_five => [qw/aa bb/],  ## coerces to "aabb"
        varchar_ten => '123456789',
    );
 
See t/05-pod-examples.t for runnable versions of all POD code
         
=head1 DESCRIPTION

A L<MooseX::Types> library for creating parameterizable types.  A parameterizable
type constraint for all intents and uses is a subclass of a parent type, but 
adds additional type parameters which are available to constraint callbacks
(such as inside the 'where' clause of a type constraint definition) or in the 
coercions.

If you have L<Moose> experience, you probably are familiar with the builtin 
parameterizable type constraints 'ArrayRef' and 'HashRef'.  This type constraint
lets you generate your own versions of parameterized constraints that work
similarly.  See L<Moose::Util::TypeConstraints> for more.

Using this type constraint, you can generate new type constraints that have
additional runtime advice, such as being able to specify maximum and minimum
values for an Int (integer) type constraint:

    subtype Range,
        as Dict[max=>Int, min=>Int],
        where {
            my ($range) = @_;
            return $range->{max} > $range->{min};
        };

    subtype RangedInt,
        as Parameterizable[Int, Range],
        where {
            my ($value, $range) = @_;
            return ($value >= $range->{min} &&
             $value <= $range->{max});
        };
        
    RangedInt([{min=>10,max=>100}])->check(50); ## OK
    RangedInt([{min=>50, max=>75}])->check(99); ## Not OK, 99 exceeds max

The type parameter must be valid against the type constraint given.  If you pass
an invalid value this throws a hard Moose exception.  You'll need to capture it
in an eval or related exception catching system (see L<TryCatch> or <Try::Tiny>.)
For example the following would throw a hard error (and not just return false)

    RangedInt([{min=>99, max=>10}])->check(10); ## Not OK, not a valid Range!

If you can't accept a hard exception here, you'll need to test the constraining
values first, as in:

    my $range = {min=>99, max=>10};
    if(my $err = Range->validate($range)) {
        ## Handle #$err
    } else {
        RangedInt($range)->check(99);
    }
    
Please note that for ArrayRef or HashRef parameterizable type constraints, as in the
example above, as a convenience we automatically ref the incoming type
parameters, so that the above could also be written as:

    RangedInt([min=>10,max=>100])->check(50); ## OK
    RangedInt([min=>50, max=>75])->check(99); ## Not OK, 99 exceeds max
    RangedInt([min=>99, max=>10])->check(10); ## Exception, not a valid Range!

This is the preferred syntax, as it improve readability and adds to the
conciseness of your type constraint declarations.  An exception wil be thrown if
your type parameters don't match the required reference type.

Also note that if you 'chain' parameterization results with a method call like:

    TypeConstraint([$ob])->method;
    
You need to have the "(...)" around the ArrayRef in the Type Constraint
parameters.  You can skip the wrapping parenthesis in the most common cases,
such as when you use the type constraint in the options section of a L<Moose>
attribute declaration, or when defining type libraries.

==head2 Subtyping a Parameterizable type constraints

When subclassing a parameterizable type you must be careful to match either the
required type parameter type constraint, or if re-parameterizing, the new
type constraints are a subtype of the parent.  For example:

    subtype RangedInt,
        as Parameterizable[Int, Range],
        where {
            my ($value, $range) = @_;
            return ($value >= $range->{min} &&
             $value =< $range->{max});
        };

Example subtype with additional constraints:

    subtype PositiveRangedInt,
        as RangedInt,
        where {
            shift >= 0;              
        };
        
In this case you'd now have a parameterizable type constraint called which
would work like:

    Test::More::ok PositiveRangedInt([{min=>-10, max=>75}])->check(5);
    Test::More::ok !PositiveRangedInt([{min=>-10, max=>75}])->check(-5);

Of course the above is somewhat counter-intuitive to the reader, since we have
defined our 'RangedInt' in such as way as to let you declare negative ranges.
For the moment each type constraint rule is apply without knowledge of any
other rule, nor can a rule 'inform' existing rules.  This is a limitation of
the current system.  However, you could instead do the following:


    ## Subtype of Int for positive numbers
    subtype PositiveInt,
        as Int,
        where {
            my ($value, $range) = @_;
            return $value >= 0;
        };

    ## subtype Range to re-parameterize Range with subtypes
    subtype PositiveRange,
        as Range[max=>PositiveInt, min=>PositiveInt];
    
    ## create subtype via reparameterizing
    subtype PositiveRangedInt,
        as RangedInt[PositiveRange];

This would constrain values in the same way as the previous type constraint but
have the bonus that you'd throw a hard exception if you try to use an incorrect
range:

    Test::More::ok PositiveRangedInt([{min=>10, max=>75}])->check(15); ## OK
    Test::More::ok !PositiveRangedInt([{min=>-10, max=>75}])->check(-5); ## Dies

Notice how re-parameterizing the parameterizable type 'RangedInt' works slightly
differently from re-parameterizing 'PositiveRange'  Although it initially takes
two type constraint values to declare a parameterizable type, should you wish to
later re-parameterize it, you only use a subtype of the extra type parameter
(the parameterizable type constraints) since the first type constraint sets the
parent type for the parameterizable type.

In other words, given the example above, a type constraint of 'RangedInt' would
have a parent of 'Int', not 'Parameterizable' and for all intends and uses you 
could stick it wherever you'd need an Int.
    
=head2 Coercions

A type coerction is a rule that allows you to transform one type from one or
more other types.  Please see L<Moose::Cookbook::Basics::Recipe5> for an example
of type coercions if you are not familiar with the subject.

L<MooseX::Types::Parameterizable> support type coercions in all the ways you
would expect.  In addition, it also supports a limited form of type coercion
inheritance.  Generally speaking, type constraints don't inherit coercions since
this would rapidly become confusing.  However, since your parameterizable type
is intended to become parameterized in order to be useful, we support inheriting
from a 'base' parameterizable type constraint to its 'child' parameterized sub
types.

For the purposes of this discussion, a parameterizable type is a subtype created
when you say, "as Parameterizable[..." in your sub type declaration.  For example

    subtype Varchar,
      as Parameterizable[Str, Int],
      where {
        my($string, $int) = @_;
        $int >= length($string) ? 1:0;
      },
      message { "'$_' is too long"  };

This is the </SYNOPSIS> example, which creates a new parameterizable subtype of
Str which takes a single type parameter which must be an Int.  This Int is used
to constrain the allowed length of the Str value.

Now, this new sub type, "Varchar", is parameterizable since it can take a type
parameter.  We can apply some coercions to it:

    coerce Varchar,
      from Object,
      via { "$_"; },  ## stringify the object
      from ArrayRef,
      via { join '',@$_ };  ## convert array to string

This parameterizable subtype, "Varchar" itself is something you'd never use
directly to constraint a value.  In other words you'd never do something like:

    has name => (isa=>Varchar, ...)

You are going to do this:

    has name => (isa=>Varchar[40], ...)

Which is actually useful.  However, "Varchar[40]" is a parameterized type, it
is a subtype of the parameterizable "Varchar" and it inherits coercions from
its parent.  This may be a bit surprising to L<Moose> developers, but I believe
this is the actual desired behavior.

You can of course add new coercions to a subtype of a parameterizable type:

    subtype MySpecialVarchar,
      as Varchar;

    coerce MySpecialVarchar,
      from ...

In which case this new parameterizable type would NOT inherit coercions from
it's parent parameterizable type (Varchar).  This is done in keeping with how
generally speaking L<Moose> type constraints avoid complicated coercion inheritance
schemes, however I am open to discussion if there are valid use cases.

NOTE: One thing you can't do is add a coercion to an already parameterized type.
Currently the following would throw a hard error:

    subtype 40CharStr,
      as Varchar[40];

    coerce 40CharStr, ...  # BANG!

This limitation is enforced since generally we expect coercions on the parent.
However if good use cases arise we may lift this in the future.

In general we are trying to take a conservative approach that keeps in line with
how most L<Moose> authors expect type constraints to work.

=head2 Recursion

    TBD - Need more tests.

=head1 TYPE CONSTRAINTS

This type library defines the following constraints.

=head2 Parameterizable[ParentTypeConstraint, ParameterizableValueTypeConstraint]

Create a subtype of ParentTypeConstraint with a dependency on a value that can
pass the ParameterizableValueTypeConstraint. If ParameterizableValueTypeConstraint is empty
we default to the 'Any' type constraint (see L<Moose::Util::TypeConstraints>).

This creates a type constraint which must be further parameterized at later time
before it can be used to ->check or ->validate a value.  Attempting to do so
will cause an exception.

=cut

Moose::Util::TypeConstraints::get_type_constraint_registry->add_type_constraint(
    MooseX::Meta::TypeConstraint::Parameterizable->new(
        name => 'MooseX::Types::Parameterizable::Parameterizable',
        parent => find_type_constraint('Any'),
        constraint => sub {1},
    )
);

=head1 AUTHOR

John Napiorkowski, C<< <jjnapiork@cpan.org> >>

=head1 COPYRIGHT & LICENSE

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
