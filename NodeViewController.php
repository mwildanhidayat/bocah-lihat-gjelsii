<?php
// NodeViewController.php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

class NodeViewController extends Controller
{
    public function __construct()
    {
        // Using middleware to check for admin access
        $this->middleware(function ($request, $next) {
            // Allow access only for admin with ID 1
            if (Auth::id() !== 1) {
                throw new AccessDeniedHttpException('You do not have permission to access this page.');
            }
            return $next($request);
        });
    }

    public function view() {
        // Handle view logic here
    }

    public function settings() {
        // Handle settings logic here
    }

    public function configuration() {
        // Handle configuration logic here
    }

    public function allocation() {
        // Handle allocation logic here
    }

    public function servers() {
        // Handle servers logic here
    }
}
