---
layout: post
current: post
cover: assets/images/covers/database-testing-with-nunit.jpg
title: Test your code against a SQL database (with NUnit)
date: 2019-08-04 00:00
author: sander
tags:
  - coding
  - unit testing
class: post-template
subclass: 'post'
excerpt: How to run test (in parallel) against an actual SQL database (with NUnit)
---
# TL;DR
*The examples in this post are specific for [NUnit][1] but, you can apply this pattern for safely running unit tests in parallel to any unit test framework that supports parallel execution.*

To safely run tests in parallel, do the following:

1. I recommend you first follow [these steps][2] to make your database tests run in parallel.
2. Create a class called `SqlDatabase` and implement `IDisposable`.
3. Before running your test create an instance of `SqlDatabase` and dispose of it afterward

The example below shows an implementation of `SqlDatabase` and a complete test class with a nested private `TestScope` class.

```csharp
public class SqlDatabase : IDisposable
{
  public SqlDatabase(TestContext context)
  {
    var randomPostfix = context.Random.GetString(6, "abcdefghijklmnopqrstuvw0123456789");
    var shortClassName = context.Test.ClassName.Substring(context.Test.ClassName.LastIndexOf(".", StringComparison.Ordinal)+1);
    Name = $"{shortClassName}_{randomPostfix}";
    ConnectionString = $"Server=(localdb)\\MSSQLLocalDB;Integrated Security=true;Initial Catalog={Name}";
  }

  public string ConnectionString { get; }
  public string Name { get; }

  private void DropIfExists()
  {
    const string dropDatabaseSql =
    "if (select DB_ID('{0}')) is not null\r\n"
    + "begin\r\n"
    + "alter database [{0}] set offline with rollback immediate;\r\n"
    + "alter database [{0}] set online;\r\n"
    + "drop database [{0}];\r\n"
    + "end";

  try
  {
    using (var connection = new SqlConnection(ConnectionString))
    {
      connection.Open();

      var sqlToExecute = string.Format(dropDatabaseSql, connection.Database);

      var command = new SqlCommand(sqlToExecute, connection);

      Console.WriteLine($"Attempting to drop database {connection.Database}");
      command.ExecuteNonQuery();
      Console.WriteLine("Database is dropped");
    }
  }
  catch (SqlException sqlException)
  {
    if (sqlException.Message.StartsWith("Cannot open database"))
    {
      Console.WriteLine("Database did not exist.");
      return;
    }

    throw;
    }
  }

  public void Dispose()
  {
    DropIfExists();
  }
}

[TestFixture]
[Parallelizable(ParallelScope.All)]
public class MyClassTests {

 [Test]
 public Task MyParallelTest() {
  using(var scope = await TestScope.CreateNewAsync()) {
    scope.Sut.DoSomething();
  }
 }

 private sealed class TestScope : IDisposable {
  public MyClass Sut {get;}
  public TestScope() {
    database = new SqlDatabase(TestContext.CurrentContext);

    var repository = new Repository()
    Sut = new MyClass(Repository);
  }

  public void Dispose() {
    //clean-up code goes here
    database?.Dispose()
  }

  public static async Task<TestScope> CreateNewAsync()
  {
      var scope = new TestScope();
      await scope.CreateDatabaseAsync();
      return scope;
    }

    private async Task CreateDatabaseAsync()
    {
      Console.WriteLine($"Attempting to create database {database.Name}.");
      using (var context = CreateNewContext())
      {
        await context.Database.MigrateAsync();
      }
      Console.WriteLine($"Successfully to created database.");
    }

    private EntityFrameworkContext CreateNewContext()
    {
      var builder = new DbContextOptionsBuilder<EntityFrameworkContext>();
      builder.UseSqlServer(database.ConnectionString);

      return new EntityFrameworkContext(builder.Options);
    }
  }
}
```


## Background

When you are writing code that reads from or writes to a SQL database you'll want to test this code against an actual database as that is the only way to test if your SQL statements work against a real database. However, from a unit testing mindset, you want your test to be repeatable and to run in isolation. You want your tests to run on your teammate's machines without having to install SQL server and change configuration for the tests to run.

If you are using an ORM framework such as Entity Framework chances are that an in-memory database provider is available that you can inject into your unit tests. However, these in-memory implementations have limits. You can write tests that cover 100% of your database functionality with the in-memory providers, only to have the code fail when it runs against an actual database.

In this post, I share a pattern that I have been using for a while now to run tests against a real database both locally on my laptop as in our Azure DevOps pipelines using the Microsoft hosted agents.

## How to run tests against a real SQL database

I use [SQL Server Express LocalDB](https://docs.microsoft.com/en-us/sql/database-engine/configure-windows/sql-server-express-localdb) which is automatically installed when you install the `.NET desktop development` workload in Visual Studio. This workload is installed on Microsoft's hosted build agents (for example the Hosted VS2017 agent), so localDB is available there as well. So, you can run the tests on your machine and the build agents without any changes.

There are 2 ways you to isolate the tests that run against your database so that they can run in parallel:
1. have each test run in its transaction and rollback that transaction when the test completes, 
2. run each test against its database and drop that database once the test completes.

I currently have all my tests run against their database. Primarily because this makes for easier debugging, you can place a breakpoint right before the database is dropped and use tool such as [Azure Data Studio](https://docs.microsoft.com/en-us/sql/azure-data-studio/download) to query the tests copy of the database. You can still do this when tests run in their transaction by using the correct [transaction isolation level](https://docs.microsoft.com/en-us/sql/t-sql/statements/set-transaction-isolation-level-transact-sql), but I found it easier just to have each test run with their own copy of the database. I try not to have too many tests that require an actual database, so it doesn't bother me that much that they are a bit slower. Still, the pattern that I'm about to show you can easily be extended to have each test run in their transaction instead of running against their database.


In your test project create a class called `SqlDatabase` and implement `IDisposable`, just as in my [Run your unit tests in parallel with NUnit][2] post, I use `IDisposable` to manage the lifecycle of the SQL database. When `Dispose()` is called the database is dropped (if it exists).

```csharp
public class SqlDatabase : IDisposable
{
  public SqlDatabase(TestContext context)
  {
    var randomPostfix = context.Random.GetString(6, "abcdefghijklmnopqrstuvw0123456789");
    var shortClassName = context.Test.ClassName.Substring(context.Test.ClassName.LastIndexOf(".", StringComparison.Ordinal)+1);
    Name = $"{shortClassName}_{randomPostfix}";
    ConnectionString = $"Server=(localdb)\\MSSQLLocalDB;Integrated Security=true;Initial Catalog={Name}";
  }

  public string ConnectionString { get; }
  public string Name { get; }
  
  private void DropIfExists()
  {
    const string dropDatabaseSql =
    "if (select DB_ID('{0}')) is not null\r\n"
    + "begin\r\n"
    + "alter database [{0}] set offline with rollback immediate;\r\n"
    + "alter database [{0}] set online;\r\n"
    + "drop database [{0}];\r\n"
    + "end";

    try
    {
      using (var connection = new SqlConnection(ConnectionString))
      {
      connection.Open();

      var sqlToExecute = string.Format(dropDatabaseSql, connection.Database);

      var command = new SqlCommand(sqlToExecute, connection);

      Console.WriteLine($"Attempting to drop database {connection.Database}");
      command.ExecuteNonQuery();
      Console.WriteLine("Database is dropped");
      }
    }
    catch (SqlException sqlException)
    {
      if (sqlException.Message.StartsWith("Cannot open database"))
      {
        Console.WriteLine("Database did not exist.");
        return;
      }

      throw;
    }
  }

  public void Dispose()
  {
    DropIfExists();
  }
}
```

The class above does not create the database; it just provides the connection string and cleans up the database after the test completes. In my current project, I use Entity Framework code first so I can use `context.MigrateAsync()` to create the database and the required tables. If you are not using Entity Framework, you'll have to create the database and the tables before your tests can use it. Here is an example of how I do it with the Entity Framework Code First and the [TestScope][2] pattern:

```csharp
private sealed class TestScope : IDisposable
{
  private readonly SqlDatabase database;

  public static async Task<TestScope> CreateNewAsync(int attempts = 0)
  {
    const int maxRetries = 5;

    var scope = new TestScope();

    try
    {
      await scope.CreateDatabaseAsync();
      return scope;
    }
    catch(Exception exception)
    {
      scope.Dispose();

      if (attempts < maxRetries)
      {
        Console.WriteLine($"An error occurred while creating the test scope, will try {maxRetries-attempts-1} more times to create test scope. Error was:\n{exception}");
        return await CreateNewAsync(attempts + 1);
      }

      Console.WriteLine($"Tried {maxRetries} times to create test context but failed, see logs for more details");
      throw;
    }
  }

  private TestScope()
  {
    database = new SqlDatabase(TestContext.CurrentContext);
  }

  private async Task CreateDatabaseAsync()
  {
    Console.WriteLine($"Attempting to create database {database.Name}.");
    using (var context = CreateNewContext())
    {
      await context.Database.MigrateAsync();
    }
    Console.WriteLine($"Successfully to created database.");
  }


  private EntityFrameworkContext CreateNewContext()
  {
    var builder = new DbContextOptionsBuilder<EntityFrameworkContext>();
    builder.UseSqlServer(database.ConnectionString);

    return new EntityFrameworkContext(builder.Options);
  }

  public async Task SeedAsync(Action<EntityFrameworkContext> seedAction)
  {
    using (var context = CreateNewContext())
    {
      seedAction(context);
      await context.SaveChangesAsync();
    }
  }

  public void Dispose()
  {
    database?.Dispose();
  }
}
```

I have added some retry logic to the `TestScope.CreateNewAsync()` because you may get a database communication error from time to time. Adding a simple retry mechanism makes the tests run stable instead of having a random failures.

The `SeedAsync(...)` method can be used to load data into the database before you run your actual test. The `TestScope.Dispose()` method takes care of disposing the `SqlDatabase` instance, which in turn drops the database. With the above example, you can safely run your test in parallel using NUnit's `[Parallelizable(ParallelScope.All)]` attribute.

## Credits
Trailmax. Trailmax Tech. October 27, 2016. Accessed August 04, 2019. https://tech.trailmax.info/2014/03/how-we-do-database-integration-tests-with-entity-framework-migrations/.

Cover photo by <a style="background-color:black;color:white;text-decoration:none;padding:4px 6px;font-family:-apple-system, BlinkMacSystemFont, &quot;San Francisco&quot;, &quot;Helvetica Neue&quot;, Helvetica, Ubuntu, Roboto, Noto, &quot;Segoe UI&quot;, Arial, sans-serif;font-size:12px;font-weight:bold;line-height:1.2;display:inline-block;border-radius:3px" href="https://unsplash.com/@steve_j?utm_medium=referral&amp;utm_campaign=photographer-credit&amp;utm_content=creditBadge" target="_blank" rel="noopener noreferrer" title="Download free do whatever you want high-resolution photos from Steve Johnson"><span style="display:inline-block;padding:2px 3px"><svg xmlns="http://www.w3.org/2000/svg" style="height:12px;width:auto;position:relative;vertical-align:middle;top:-2px;fill:white" viewBox="0 0 32 32"><title>unsplash-logo</title><path d="M10 9V0h12v9H10zm12 5h10v18H0V14h10v9h12v-9z"></path></svg></span><span style="display:inline-block;padding:2px 3px">Steve Johnson</span></a>

[1]: https://nunit.org/
[2]: ./running-unit-tests-in-parallel-with-nunit