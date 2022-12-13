---
header:
  overlay_image: assets/images/covers/grpc-aspnetcore-azure-ad-authentication.jpg
  teaser: assets/images/covers/grpc-aspnetcore-azure-ad-authentication.jpg
title: Use Azure AD authentication with gRPC.
date: 2019-04-08 00:00
author: sander
tags:
  - coding
  - aspnetcore
  - grpc
excerpt: How to setup a gRPC service in ASP.NET core 3.0 using Azure AD for authentication.
---
# TL;DR

Have a look at [this example](https://github.com/sanderaernouts/GrpcAuthDemo) on GitHub for an example application using ASP.NET core 3.0 to host a gRPC service that uses AzureAD for authentication.

## Background

I wanted to look into [gRPC](https://grpc.io/) for a while now, so during our innovation day at [Xpirit](https://xpirit.com/) last Friday my colleague [Marc Bruins](https://www.marcbruins.nl) and I took our chance and explored what gRPC is, how to use it with ASP.NET core, and how you can Azure AD authentication to it. What gRPC is and how you can use it with ASP.NET core is pretty well documented, so instead the focus is on how to add Azure AD authentication to it. **Spoiler alert**: it is straightforward, it was just hard to find good examples.

By default, gRPC runs on top of HTTP2, and it is essential to keep that in mind. It took us a while to figure out how to add authentication to gRPC, but once we realized it is "just HTTP" it got a lot easier. In the end, adding authentication with JWT tokens to a gRPC server is as simple as sending an `Authorization` header with your JWT token and wiring up the correct ASP.NET core middleware on the server just as you would do for a regular HTTP API.

Currently, [grpc-dotnet](https://github.com/grpc/grpc-dotnet) is adding first class support for gRPC to ASP.NET Core 3. There is even a project template for gRPC available now as part of the .NET core 3.0 preview SDK. We will use this template as base and add authtication to it.

## Create a gRPC service

To get started, create a new ASP.NET core 3.0 preview project and select the `gRPC Service` template. To be able to use Azure AD based authentication, add these 2 packages to your server project:

```xml
<PackageReference Include="Microsoft.AspNetCore.Authentication.AzureAD.UI" Version="3.0.0-preview3-19153-02" />
<PackageReference Include="Microsoft.AspNetCore.Mvc.NewtonsoftJson" Version="3.0.0-preview3-19153-02" />
```

The configuration for Azure AD is read from the `appsettings.json`, so we need access to `IConfiguration`. To enable this add this constructor and public property to `Startup.cs`:

```csharp
//......
public Startup(IConfiguration configuration)
{
    Configuration = configuration;
}

public IConfiguration Configuration { get; }
//......
```

We can use the "normal" ASP.NET core authentication and authorization functionality, just as we would for an HTTP REST API. To configure this change the `ConfigureServices` method in `Startup.cs` to this:

```csharp
public void ConfigureServices(IServiceCollection services)
{
    services.AddHttpContextAccessor();

    services.AddAuthorization();
    services.AddAuthorizationPolicyEvaluator();
    services.AddAuthentication(AzureADDefaults.BearerAuthenticationScheme)
      .AddAzureADBearer(options => Configuration.Bind("AzureAd", options));

    services.AddGrpc(options =>
    {
        options.EnableDetailedErrors = true;
    });
}
```

To configure authorization for the gRPC service endpoint, add `.RequireAuthorization()` to the route configuration. Also, add the authentication and authorization middleware. To enable this, in `Startup.cs` change the `Configure` method to this:

```csharp
public void Configure(IApplicationBuilder app, IWebHostEnvironment env)
{
    if (env.IsDevelopment())
    {
        app.UseDeveloperExceptionPage();
    }

    app.UseRouting(routes => {
      routes.MapGrpcService<ContentStoreImpl>()
        .RequireAuthorization();
      }
    );

    app.UseAuthentication();
    app.UseAuthorization();
}
```

Now configure the required Azure AD settings in `appsettings.json` file:

```json
{
  //........
  "AzureAd": {
    "Instance": "https://login.microsoftonline.com/",
    "Domain": "sanderaernoutssupersecret.onmicrosoft.com",
    "TenantId": "67fa4d25-d682-4fc0-827f-fe0a3dc07fbf",
    "ClientId": "bb063c8e-0600-4627-8927-ae6e7fa2d5a7"
  }
  //........
}
```

Change `GreeterService.cs` to this (add an`Authorize` attribute):

```csharp
[Authorize]
public class GreeterService : Greeter.GreeterBase
{
    public override Task<HelloReply> SayHello(HelloRequest request, ServerCallContext context)
    {
        return Task.FromResult(new HelloReply
        {
            Message = "Hello " + request.Name
        });
    }
}
```

Finally in change the client to send a `Authorize` HTTP header with a JWT token to the server:

```csharp
//.....
var token = "<token>";
var metadata = new Metadata
{
    { "Authorization", $"Bearer {token}"}
});

var reply = await client.SayHelloAsync(new HelloRequest { Name = "GreeterClient" }, metadata);
//....
```

Let's add the name of the `IUserIdentity` to the message to prove we have authenticated with an Azure AD user.

```csharp
namespace GrpcAuthDemo
{
    [Authorize]
    public class GreeterService : Greeter.GreeterBase
    {
        public override Task<HelloReply> SayHello(HelloRequest request, ServerCallContext context)
        {
            var httpContenxt = context.GetHttpContext();
            var user = httpContenxt.User;
            return Task.FromResult(new HelloReply
            {
                Message = $"Hello {request.Name} (logged in as: {user.Identity.Name})"
            });
        }
    }
}
```

Now run the example (with a valid JWT token), and you should see something like this:

```text
Greeting: Hello GreeterClient (logged in as: live.com#sander.aernouts@supersecret.com)
```

Note that the client connect over plain HTTP instead of HTTPS(an SSL encrypted connection), which is fine for our localhost example. See [this](https://grpc.io/docs/guides/auth.html#authenticate-a-single-rpc-call) section of the gRPC documentation to setup SSL encryption.

## Credits

Cover photo by <a style="background-color:black;color:white;text-decoration:none;padding:4px 6px;font-family:-apple-system, BlinkMacSystemFont, &quot;San Francisco&quot;, &quot;Helvetica Neue&quot;, Helvetica, Ubuntu, Roboto, Noto, &quot;Segoe UI&quot;, Arial, sans-serif;font-size:12px;font-weight:bold;line-height:1.2;display:inline-block;border-radius:3px" href="https://unsplash.com/@wizwow?utm_medium=referral&amp;utm_campaign=photographer-credit&amp;utm_content=creditBadge" target="_blank" rel="noopener noreferrer" title="Download free do whatever you want high-resolution photos from Donald Giannatti"><span style="display:inline-block;padding:2px 3px"><svg xmlns="http://www.w3.org/2000/svg" style="height:12px;width:auto;position:relative;vertical-align:middle;top:-2px;fill:white" viewBox="0 0 32 32"><title>unsplash-logo</title><path d="M10 9V0h12v9H10zm12 5h10v18H0V14h10v9h12v-9z"></path></svg></span><span style="display:inline-block;padding:2px 3px">Donald Giannatti</span></a>