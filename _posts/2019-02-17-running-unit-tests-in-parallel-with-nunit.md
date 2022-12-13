---
header:
  overlay_image: assets/images/covers/running-unit-tests-in-parallel-with-nunit.jpg
  teaser: assets/images/covers/running-unit-tests-in-parallel-with-nunit.jpg
title: Run your unit tests in parallel with NUnit
date: 2019-02-16 12:00
author: sander
tags:
  - coding
  - unit testing
excerpt: How to safely run unit tests in parallel using NUnit. Examples in are specific for NUnit but, you can apply this pattern to any other test framework that supports parallel execution.
---
# TL;DR

*The examples in this post are specific for [NUnit][1] but, you can apply this pattern for safely running unit tests in parallel to any unit test framework that supports parallel execution.*

To safely run tests in parallel, do the following:

1. Mark your test fixtures with the `Parallelizable` attribute and set the parallel scope to `ParallelScope.All`.
2. Create a private class called `TestScope` and implement `IDisposable`.
3. Put all startup and clean-up logic inside the `TestScope` constructor and `.Dispose()` method respectively.
4. Wrap your test code in a `using (var scope = new TestScope) { ... }` block

The example below shows a complete test class with a nested private `TestScope` class.

```csharp
[TestFixture]
[Parallelizable(ParallelScope.All)]
public class MyClassTests {

    [Test]
    public void MyParallelTest() {
        using(var scope = new TestScope()) {
            scope.Sut.DoSomething();
            scope.Repository.Received(1).Save();
        }
    }

    private sealed class TestScope : IDisposable {
        public IRepository Repository{get;}
        public MyClass Sut {get;}
        public TestScope() {
            Repository = Substitute.For<IRepository>();
            Sut = new MyClass(Repository);
        }

        public void Dispose() {
            //clean-up code goes here
            Repository?.Dispose()
        }
    }
}
```

## Background

Running unit tests in parallel can significantly improve the speed at which they run. However, you have to make sure that one test does not affect another in any way. Else your tests are green most of the time, but sometimes one or more tests will fail.

Take for example these two tests:

```csharp
[TestFixture]
[Parallelizable(ParallelScope.All)]
public class MyClassTests {
    private IRepository repository

    [SetUp]
    public void SetUp() {
        repository = Substitute.For<IRepository>();
    }

    [Test]
    public void Test1() {
        var sut = new MyClass(repository);
        sut.Read()

        repository.DidNotReceive().Save();
    }

    [Test]
    public void Test2() {
        var sut = new MyClass(repository);
        sut.SaveAll()

        repository.Received(1).Save();
    }
}
```

Both tests depend on `IRepository`. One test verifies that `.ReadAll()` does not call the `.Save()` method and the other test verifies that `.SaveAll()` calls the `.Save()` method exactly once.

[NUnit][1] calls the `SetUp` method just before it calls each test method. That sounds like what we want but, [NUnit][1] creates a single instance of your test class and calls the `SetUp` and test methods on that single instance. So all of the tests in this class potentially use the same instance of `IRepository` when they happen to run at the same time. Which in turn means one test can interfere with another. This problem only occurs if you run tests in parallel by using the `Parallelizable` attribute with a parallel scope that allows test in your fixture to run at the same time.

If you have a sufficient number of other tests, these tests are green most of the time because the chances of them interfering with each other are limited. However, theywill fail at random intervals. If you configure all tests in your test project(s) to run in parallel, tests go red at random in different places.

You can configure [NUnit][1] to only run tests in one fixture in parallel with tests in another fixture, but this limits the amount of parallelism that can occur when [NUnit][1] is executing your tests and may not give you the best performance in terms of test execution time.

## How to safely run tests in parallel

To allow tests to run in parallel without them interfering with each other, I have been applying the following pattern for a while:

1. Create a nested private `TestScope` class that implements `IDisposable`.
2. All initialization or startup code that would go into the `SetUp` method goes into the constructor of the `TestScope` class.
3. Any clean-up or teardown code that would go into the `TearDown` method goes into the `Dispose` method
4. All tests run inside a `using` block that handles the creation and disposal of the `TestScope`.

Below is an example of such a test class:

```csharp
[TestFixture]
[Parallelizable(ParallelScope.All)]
public class MyClassTests {

    [Test]
    public void MyParallelTest() {
        using(var scope = new TestScope()) {
            scope.Sut.DoSomething();
            scope.Repository.Received(1).Save();
        }
    }

    private sealed class TestScope : IDisposable {
        public IRepository Repository{get;}
        public MyClass Sut {get;}
        public TestScope() {
            Repository = Substitute.For<IRepository>();
            Sut = new MyClass(Repository);
        }

        public void Dispose() {
            //clean-up code goes here
            Repository?.Dispose()
        }
    }
}
```

*This example is specific for [NUnit][1] but you can use this pattern with any test framework that supports parallel testing.*

I like this pattern because it is very explicit about what is inside the scope of the test that is currently running. Also, no other test can have accesses to the same scope, so it is safe to use `ParallelScope.All` to run your tests in parallel with any other test. You can also add public helper methods on the `TestScope` class to for example grant or deny permissions, enable or disable feature flags, or add test data to a database.

If you require any asynchronous initialization code you can add a static `async` factory method to the `TestScope` class and use it to create the `TestScope` instance:

```csharp
...
[Test]
public async Task MyParallelTest() {
    using(var scope = await TestScope.CreateAsync()) {
        scope.Sut.DoSomething();
        scope.Repository.Received(1).Save();
    }
}
...
```

## Maximizing parallel execution with Visual Studio

[NUnit][1] takes care of running tests in parallel that are in the same assembly. However, if you want multiple test assemblies to run in parallel you have to configure the Visual Studio test runner to do that. You can do this by enabling the following option:

![Enable parallel test execution in Visual Studio](assets/images/posts/running-unit-tests-in-parallel-with-nunit/visual-studio-parallel-test-assemblies.png)

## Maximizing parallel execution with Azure DevOps

When you run a CI build in Azure DevOps you have to configure the build task that runs the tests to run them in parallel. If you use the Visual Studio Test task, you can do this by enabling the followin option:

![Enable parallel test execution in Azure DevOps](assets/images/posts/running-unit-tests-in-parallel-with-nunit/azure-dev-ops-parallel-test-assemblies.png)

## Caveats

The main problem with running tests in parallel is that you have to make sure no single test can influence the outcome of any other tests. Here are a few examples of things you have to keep in mind:

1. If your test depends on a database (in-memory, local, or remote), each test should have a unique and clean copy of that database.
2. If your test depends on an in-memory ASP.net core server, each test should have a unique instance.
3. If your test depends on Azure blob storage or the Azure Storage Emulator, each test should have its unique container, subfolder, table, or queue.

In short your test should have a unique instance or clean copy of whatever it depends on to make sure it can truly run in parallel. This applies to any dependency whether is it a mock or substitute, a file, a directory, or a database.

Most of this you get for free if you put all the startup or initialization logic for tests in the constructor of the `TestScope` class.

## Credits

Cover photo by <a style="background-color:black;color:white;text-decoration:none;padding:4px 6px;font-family:-apple-system, BlinkMacSystemFont, &quot;San Francisco&quot;, &quot;Helvetica Neue&quot;, Helvetica, Ubuntu, Roboto, Noto, &quot;Segoe UI&quot;, Arial, sans-serif;font-size:12px;font-weight:bold;line-height:1.2;display:inline-block;border-radius:3px" href="https://unsplash.com/@dnevozhai?utm_medium=referral&amp;utm_campaign=photographer-credit&amp;utm_content=creditBadge" target="_blank" rel="noopener noreferrer" title="Download free do whatever you want high-resolution photos from Denys Nevozhai"><span style="display:inline-block;padding:2px 3px"><svg xmlns="http://www.w3.org/2000/svg" style="height:12px;width:auto;position:relative;vertical-align:middle;top:-2px;fill:white" viewBox="0 0 32 32"><title>unsplash-logo</title><path d="M10 9V0h12v9H10zm12 5h10v18H0V14h10v9h12v-9z"></path></svg></span><span style="display:inline-block;padding:2px 3px">Denys Nevozhai</span></a>

[1]: https://nunit.org/