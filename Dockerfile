# ==========================================
# STAGE 1: Build the React Frontend (Vite)
# ==========================================
FROM node:20 AS build-client
WORKDIR /app/ssa.client

# Pass the Google Client ID as a build argument into Vite
ARG VITE_GOOGLE_CLIENT_ID
ENV VITE_GOOGLE_CLIENT_ID=$VITE_GOOGLE_CLIENT_ID

# Copy package.json and install dependencies
COPY ssa.client/package*.json ./
RUN npm install

# Copy frontend source and build it
COPY ssa.client/ ./
RUN npm run build

# ==========================================
# STAGE 2: Build the .NET 8 Backend
# ==========================================
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build-server
WORKDIR /app

# Copy the solution and project files first to cache NuGet restore
COPY *.sln ./
COPY ssa.server/ssa.server.csproj ssa.server/
COPY ssa.client/ssa.client.esproj ssa.client/

# Restore NuGet dependencies
RUN dotnet restore "ssa.server/ssa.server.csproj"

# Copy the rest of the backend source code
COPY ssa.server/ ssa.server/

# Publish the .NET app
WORKDIR /app/ssa.server
RUN dotnet publish "ssa.server.csproj" -c Release -o /app/publish /p:UseAppHost=false /p:NoClientBuild=true

# Copy the compiled React files (from STAGE 1) into the published wwwroot
COPY --from=build-client /app/ssa.client/dist /app/publish/wwwroot

# ==========================================
# STAGE 3: Final Runtime Image
# ==========================================
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

# Expose ports (Cloud Run uses the PORT environment variable, usually 8080)
EXPOSE 8080
ENV ASPNETCORE_URLS=http://*:${PORT:-8080}

# Copy the final published output from Stage 2
COPY --from=build-server /app/publish .

# Tell the container what command to run on startup
ENTRYPOINT ["dotnet", "ssa.server.dll"]
