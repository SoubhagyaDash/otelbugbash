FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY ["dotnet-service.csproj", "./"]
RUN dotnet restore "dotnet-service.csproj"

COPY . .
RUN dotnet build "dotnet-service.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "dotnet-service.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
EXPOSE 5000

COPY --from=publish /app/publish .

ENV ASPNETCORE_URLS=http://+:5000
ENV ASPNETCORE_ENVIRONMENT=Production

ENTRYPOINT ["dotnet", "dotnet-service.dll"]
