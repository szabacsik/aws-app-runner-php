<?php

declare(strict_types=1);

use Phalcon\Mvc\Micro;
use Phalcon\Http\Response;

// Create a new Phalcon Micro application
$app = new Micro();

// CORS preflight handler
$app->options('/{catch:.*}', function () {
    $r = new Response();
    $r->setHeader('Access-Control-Allow-Origin', '*');
    $r->setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    $r->setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    return $r;
});

// Set up the main route
$app->get('/', function () {
    $response = new Response();
    $response->setContentType('application/json', 'UTF-8');
    $response->setHeader('X-Content-Type-Options', 'nosniff');
    $response->setHeader('Referrer-Policy', 'no-referrer');
    $response->setHeader('Access-Control-Allow-Origin', '*');

    // App metadata from environment
    $appEnv     = getenv('APP_ENV')     ?: 'unknown';
    $appName    = getenv('APP_NAME')    ?: 'php-app';
    $appVersion = getenv('APP_VERSION') ?: 'latest';
    $response->setHeader('X-App-Env', $appEnv);

    // Get request information
    $request = $this->request;
    $method = $request->getMethod();
    $path = $request->getURI();
    $query = $request->getQuery();

    // Prepare response data
    $responseData = [
        'status' => 'success',
        'message' => 'Phalcon REST API is working',
        'core' => [
            'php_version' => phpversion(),
            'env' => $appEnv,
            'hostname' => gethostname(),
        ],
        'framework' => [
            'name' => 'Phalcon',
            'version' => phpversion('phalcon'),
        ],
        'app' => [
            'name' => $appName,
            'version' => $appVersion,
        ],
        'data' => [
            'method' => $method,
            'path' => $path,
            'query' => $query,
            'time' => new DateTimeImmutable('now', new DateTimeZone('UTC'))->format(DATE_ATOM),
        ]
    ];

    $response->setJsonContent($responseData);
    return $response;
});

// Health check endpoint (improved)
$app->map('/health', function () {
    $response = new Response();
    $response->setStatusCode(200, 'OK');
    $response->setContentType('text/plain', 'UTF-8');
    $response->setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
    $response->setHeader('Pragma', 'no-cache');
    $response->setHeader('X-Content-Type-Options', 'nosniff');
    $response->setHeader('Referrer-Policy', 'no-referrer');
    $response->setHeader('Access-Control-Allow-Origin', '*');
    $response->setHeader('X-App-Env', getenv('APP_ENV') ?: 'unknown');

    $method = $this->request->getMethod();
    if ($method === 'HEAD') {
        // No body for HEAD requests
        return $response;
    }

    $response->setContent('OK');
    return $response;
})->via(['GET', 'HEAD']);

// Handle other routes with a catch-all
$app->notFound(function () {
    $response = new Response();
    $response->setContentType('application/json', 'UTF-8');
    $response->setStatusCode(404, 'Not Found');
    $response->setHeader('X-Content-Type-Options', 'nosniff');
    $response->setHeader('Referrer-Policy', 'no-referrer');
    $response->setHeader('Access-Control-Allow-Origin', '*');

    $request = $this->request;

    $responseData = [
        'status' => 'error',
        'message' => 'Endpoint not found',
        'framework' => [
            'name' => 'Phalcon',
            'version' => phpversion('phalcon')
        ],
        'data' => [
            'method' => $request->getMethod(),
            'path' => $request->getURI(),
            'available_endpoints' => [
                'GET /' => 'Main API status endpoint',
                'GET /health' => 'Health check endpoint'
            ]
        ]
    ];

    $response->setJsonContent($responseData);
    return $response;
});

// Handle the application
try {
    $app->handle($_SERVER['REQUEST_URI']);
} catch (Throwable $e) {
    $response = new Response();
    $response->setContentType('application/json', 'UTF-8');
    $response->setStatusCode(500, 'Internal Server Error');
    $response->setHeader('X-Content-Type-Options', 'nosniff');
    $response->setHeader('Referrer-Policy', 'no-referrer');
    $response->setHeader('Access-Control-Allow-Origin', '*');

    $responseData = [
        'status' => 'error',
        'message' => 'Internal server error',
        'framework' => [
            'name' => 'Phalcon',
            'version' => phpversion('phalcon')
        ],
        'error' => $e->getMessage()
    ];

    $response->setJsonContent($responseData);
    $response->send();
}
