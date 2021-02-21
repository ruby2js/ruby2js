---
top_section: Stimulus
title: Tips & Gotchas
order: 17
next_page_order: 21
category: tips
---

In a few short pages we have covered a lot of ground, but really we have only
scratched the surface of what Ruby2JS can do.  These pages make it look easy,
but there are a few things to watch out for.

 * Parenthesis

     There is a fundamental mismatch between the Ruby and JavaScript object
     models.  In Ruby, classes have methods, some of which may be attribute
     accessors.  In JavaScript, classes have properties, some of which may be
     functions.  This makes it impossible to distinguish between calls to
     methods with zero arguments and property accesses.  Following Ruby's
     model (everything is a method call) would make it impossible to acccess
     JavaScript properties.  Following JavaScript's model of everything is a
     property would make it impossible to call a method with zero arguments.

     Ruby2JS solves this by detecting the use of parenthesis to distinguish
     between these two cases.  First, the rules of thumb, and then some of the
     significant exceptions:

     * **Always** use parenthesis on method definitions when there are zero
       arguments.
     * **Always** use parenthesis on method calls when there are zero
       arguments.
     * **Never** use parenthesis on definitions of attribute reader / property
       getters.

     If you follow these rules, you will never have a problem.  All but the
     last example ([Content Loader](content-loader)) followed these rules.

     The lack of strong typing in both Ruby and JavaScript makes exceptions
     difficult as type inferencing will only get you so far.  The one
     exception is the value of `this` / `self` within the definition of
     classes, the type of which is always very much known.

     If you are careful on your method and accesssor *definitions*, then
     *references* to these methods and attributes within the class can be
     determined at compile time, enabling the omission of parenthesis in
     intra-class calls even when there are no arguments.

     It just so happens that Stimulus hits this sweet spot as every definition
     is a class.

 * Returns

     In Ruby, every statement is an expression and returns a value.  The
     `return` statement at the end of a method is therefore optional.  This is
     not the case with JavaScript.  There are a few cases (attribute readers
     being an obvious example), where the need for a return statement can be
     inferred and is inserted automatically by Ruby2JS, but in general, if you
     define a method and want to return a value, you need a `return` statement.

     This is not much of a problem for Stimulus as neither lifecycle methods
     nor actions are expected to return a result.

     One solution that may be a bit of overkill: the
     [return](../../docs/filters/return) filter that adds a return statement
     to **every** method defintion.  This generally is harmless, but may make
     the generated code marginally bigger and marginally less readable.

 * Explore!

     In Stiumuls, everything is a class.  Classes in both Ruby and JavaScript
     have inheritance hierarchies, are open, can have mixins by including
     modules, etc.  The [require](../../docs/filters/require) filter can help
     by turning Ruby `require` statements into JavaScript `import` statements.

Got questions or comments?  Join the [community](../../docs/community)!
